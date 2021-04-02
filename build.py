#!/usr/bin/env python3
#
# Copyright 2020-2021 Josua Mayer <josua@solid-run.com>
#

from kiwi.command import Command
from kiwi.defaults import Defaults
from kiwi.filesystem import FileSystem
from kiwi.mount_manager import MountManager
from kiwi.storage.disk import Disk
from kiwi.storage.loop_device import LoopDevice
from kiwi.system.prepare import SystemPrepare
from kiwi.system.setup import SystemSetup
from kiwi.system.size import SystemSize
from kiwi.utils.block import BlockID
from kiwi.xml_description import XMLDescription
from kiwi.xml_state import XMLState

from abc import ABC, abstractmethod
from glob import glob
import logging
import math
import os
from xmlschema import XMLSchema, XMLSchemaException

##
### Logging
###
logger = logging.getLogger('kiwi')
logger.setLogLevel(logging.INFO)

###
### Helper
###

class Section(ABC):
	@abstractmethod
	def path(self):
		pass

	@abstractmethod
	def offset(self):
		pass

	@abstractmethod
	def size(self):
		pass

	@abstractmethod
	def finalize(self, image):
		pass

	@abstractmethod
	def set_device(self, device):
		pass

class BlobSection(Section):
	def __init__(self, path, offset=None):
		self._offset = offset
		self._path = path
		fd = os.open(path, os.O_RDONLY)
		stat = os.fstat(fd)
		os.close(fd)
		self._size = stat.st_size

	def path(self):
		return self._path

	def offset(self):
		return self._offset

	def size(self):
		return self._size

	def finalize(self, image):
		return True

	def set_device(self, device):
		return True

class KiwiRootfsSection(Section):
	def __init__(self, path, state, offset=None):
		self._device = None
		self._offset = offset
		self._path = path
		self._state = state

		sz = SystemSize(path)
		self._size = sz.customize(size=sz.accumulate_mbyte_file_sizes(), requested_filesystem='ext4') * 1024 * 1024

	def path(self):
		return self._path

	def offset(self):
		return self._offset

	def size(self):
		return self._size

	def finalize(self, image):
		# mount fs
		mount = MountManager(device=self._device)
		mount.mount(options=None)

		# run post-image script
		setup = SystemSetup(xml_state=self._state, root_dir=mount.mountpoint)
		setup.import_description()
		setup.call_disk_script()

		# clean-up
		mount.umount()
		del setup
		return True

	def set_device(self, device):
		self._state.set_root_partition_uuid(uuid=BlockID(device=device).get_blkid('PARTUUID'))
		self._device = device
		return True

def PrepareBlobSection(source, offset):
	# wrap into object
	return BlobSection(path=source, offset=offset)

def PrepareKiwiRootfsSection(descdir, destdir, offset=None):
	# initialize state
	state = XMLState(XMLDescription(descdir + '/config.xml').load())

	# collct signing keys
	repokeys = glob(descdir + '/*.key')

	# install chroot
	system = SystemPrepare(xml_state=state, root_dir=destdir, allow_existing=True)
	pkgmanager = system.setup_repositories(clear_cache=False, signing_keys=repokeys)
	system.install_bootstrap(manager=pkgmanager, plus_packages=None)
	pkgmanager.root_dir = destdir
	system.install_system(manager=pkgmanager)

	# configure chroot
	setup = SystemSetup(xml_state=state, root_dir=destdir)
	setup.import_description()
	setup.setup_groups()
	setup.setup_users()
	setup.call_config_script()

	# clean
	del pkgmanager
	del setup
	del system

	return KiwiRootfsSection(path=destdir, state=state, offset=offset)

def PrepareSection(args, destdir):
	name = args["@name"]
	offset = int(args["@offset"])
	type = args["@type"]

	logger.info(f'Building section \"{ name }\"')
	# python 3.10 preparation
	#match type:
	#	case "blob":
	#		return BuildBlobSection(name=name, source=args["@source"], offset=offset)
	#	case "rootfs":
	#		return BuildRootfsSection(name=name, source=args["@source"])
	#	case _:
	#		logger.error(f'encountered invalid section type \"{ type }\"')
	#		return False
	if type == "blob":
		return PrepareBlobSection(source=args["@source"], offset=offset)
	elif type == "rootfs":
		return PrepareKiwiRootfsSection(descdir=args["@source"], destdir=f'{destdir}/{name}', offset=offset)
	else:
		logger.error(f'encountered invalid section type \"{ type }\"')
		return None

def FinalizeSection(section, image):
	return section.finalize(image=image)

class KiwiDiskImage:
	def __init__(self, path, size):
		# don't allocate kiwi disk object
		self._disk = None

		# allocate file-backed loop-device
		mbytes = math.ceil(size/(1024*1024))
		self._lodev = LoopDevice(filename=path, filesize_mbytes=mbytes, blocksize_bytes=None)
		self._lodev.create(overwrite=True)

	def AddSection(self, section):
		if isinstance(section, BlobSection):
			ret = self.AddBlob(path=section.path(), offset=section.offset())
			return ret
		elif isinstance(section, KiwiRootfsSection):
			ret = self.AddRootfs(path=section.path(), offset=section.offset())
			if ret:
				section.set_device(device=self._disk.get_device()['root'].get_device())
			return ret
		else:
			return False

	def AddPartitionTable(self):
		self._disk = Disk(table_type='msdos', storage_provider=self._lodev, start_sector=None)
		return True

	def AddRootfs(self, path, fstype='ext4', offset=None):
		sector_offset = None
		if not offset is None:
			if (offset % 512) != 0:
				logger.error(f'given rootfs offset { offset } is not multiple of 512!')
				return False
			sector_offset = int(offset / 512)

		# kiwi does not directly allow manipulating partition offset directly
		# this setting only works for the initial gap to the first partition ...
		# also, this call relies on implementation details!
		self._disk.partitioner.start_sector = sector_offset

		self._disk.create_root_partition(mbsize='all_free')
		self._disk.map_partitions()
		system = FileSystem.new(name=fstype, device_provider=self._disk.get_device()['root'], root_dir=f'{ path }/', custom_args=None)
		system.create_on_device(label=None)
		system.sync_data(exclude=None)
		del system
		return True

	def AddBlob(self, path, offset):
		bs = 1
		if 0 == (offset % 512):
			bs = 512
			offset = int(offset / 512)

		Command.run(command=['dd', 'conv=notrunc', f'of={ self._lodev.get_device() }', f'if={ path }', f'bs={ bs }', f'seek={ offset }'])
		return True

	def __del__(self):
		# free kiwi disk object, if any
		if not self._disk is None:
			del self._disk

		# free loop-device
		del self._lodev

###
### MAIN
###
if __name__ == "__main__":
	# load configuration
	config = None
	logger.info(f'Loading configuration')
	try:
		schema =  XMLSchema('config.xsd')
		schema.validate('config.xml')
		config = schema.to_dict('config.xml')
	except XMLSchemaException as error:
		logger.error(error)
		exit(1)

	# create top-level build directory
	pwd = os.path.dirname(os.path.realpath(__file__))
	if not os.path.isdir(f'{ pwd }/build'):
		os.mkdir(path=f'{ pwd }/build')

	# save debug log to file
	logger_filehandler = logging.FileHandler(f'{ pwd }/build/debug.log')
	logger_filehandler.setLevel(logging.DEBUG)
	logger.addHandler(logger_filehandler)

	# configure kiwi
	Defaults.set_shared_cache_location(f'{ pwd }/build/cache')

	# iterate over images
	for image in config["image"]:
		logger.info(f'Building \"{ image["@name"] }\" ...')

		# prepare sections (pre-image)
		sections=[]
		for section in image["section"]:
			# build section
			ret = PrepareSection(args=section, destdir=f'{ pwd }/build/{ image["@name"] }')
			if ret is None:
				exit(1)
			sections.append(ret)

		# estimate minimal disk image size
		size = 512 # space for MBR
		for section in sections:
			offset = section.offset()
			if offset is None:
				# no offset means place anywhere -> only size counts
				size += section.size()
			else:
				# use end of section
				size = max(size, offset + section.size())

		# create disk image
		disk = KiwiDiskImage(path=f'{ pwd }/build/{ image["@name"] }.img', size=size)
		disk.AddPartitionTable()
		for section in sections:
			if not disk.AddSection(section):
				exit(1)

		# finalize sections (post-image)
		for section in sections:
			if not FinalizeSection(section=section, image=disk):
				exit(1)

		logger.info(f'Building \"{ image["@name"] }\": Done')

	# end
	exit(0)

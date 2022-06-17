#!/usr/bin/env python3
#
# Copyright 2022 Josua Mayer <josua@solid-run.com>
#

import argparse
import hashlib
import os
import shutil
from string import Template
import subprocess
from subprocess import Popen
import tempfile
import urllib.request

def CheckHash(path, algorithm, hash):
	h = hashlib.new(algorithm)

	with open(path, 'rb') as f:
		while chunk := f.read(8192):
			h.update(chunk)

	return h.hexdigest() == hash

def FetchPackagesSourceFiles(destdir, listfile):
	if not os.path.isdir(destdir):
		os.mkdir(path=destdir)

	with open(listfile, "r") as list:
		for entry in list:
			url, path, name, hashalg, hash = entry.split()
			outpath = os.path.join(destdir, path, name)
			print(f'fetching { outpath } from { url } ...')

			if not os.path.isdir(os.path.join(destdir, path)):
				os.mkdir(path=os.path.join(destdir, path))

			if os.path.isfile(outpath):
				if CheckHash(path=outpath, algorithm=hashalg, hash=hash):
					print(f'file exists and checksum matches, skipping download')
					continue

			with urllib.request.urlopen(url) as r, open(outpath, 'wb') as f:
				shutil.copyfileobj(r, f)

			if not CheckHash(path=outpath, algorithm=hashalg, hash=hash):
				print(f'Error: checksum does not match!')
				return False

	return True

def FetchPackagesSourceRepo(manifestrepo, destdir, manifest):
	if not os.path.isdir(destdir):
		os.mkdir(path=destdir)

	if not os.path.isdir(f'{ destdir }/.repo'):
		process = subprocess.run(['repo', 'init', '-u', manifestrepo, '-m', 'package-recipes/empty.xml'], cwd=destdir)
		os.mkdir(path=f'{ destdir }/.repo/local_manifests')
		os.symlink(src=manifest, dst=f'{ destdir }/.repo/local_manifests/manifest.xml')

	process = subprocess.run(['repo', 'sync', '--fetch-submodules', '-j2'], cwd=destdir)

def BuildPackage(sourcedir, builddir, hostarch, extrarepo=None):
	if not os.path.isdir(builddir):
		os.mkdir(path=builddir)

	pkgsource = None
	pkgsourcedir = os.path.join(sourcedir, 'pkgsrc')
	if os.path.isdir(pkgsourcedir):
		# ensure control-file exists
		pkgsourcecontrolfile = os.path.join(pkgsourcedir, 'debian', 'control')

		if not os.path.isfile(pkgsourcecontrolfile):
			#  last resort: maybe there is a rule to make it
			print(f'Trying to generate { pkgsourcecontrolfile }!')
			process = subprocess.run(['make', '-f', 'debian/rules', 'debian/control'], cwd=pkgsourcedir)

		if os.path.isfile(pkgsourcecontrolfile):
			pkgsource = pkgsourcedir
	else:
		# look for a source package file
		pkgsourcefile = None
		for entry in os.scandir(sourcedir):
			if entry.is_file() and entry.name.endswith('.dsc'):
				if not pkgsourcefile is None:
					print('Error: Found multiple source packages in { sourcedir }!')
					return False

				pkgsourcefile = os.path.join(sourcedir, entry.name)

		if not pkgsourcefile is None:
			pkgsource = pkgsourcefile

	if pkgsource is None:
		print(f'Error: Found no source package in { sourcedir }!')
		return False

	print(f'Building { pkgsource }!')
	if not extrarepo is None:
		process = subprocess.run(['sbuild', '--dist', 'bullseye', '--host', hostarch, '--arch-all', '-j5', f'--extra-repository={ extrarepo }', f'--pre-build-commands=%e sh -c "install -m755 -d /usr/src/packages/SOURCES"', f'--pre-build-commands=find { sourcedir } -maxdepth 1 -name "*.bin" | cpio -H ustar -o | %e tar --show-transformed-names --transform "s;^.*/;;" -C /usr/src/packages/SOURCES -xvf -', pkgsource], cwd=builddir)
	else:
		process = subprocess.run(['sbuild', '--dist', 'bullseye', '--host', hostarch, '--arch-all', '-j5', f'--pre-build-commands=%e sh -c "install -m755 -d /usr/src/packages/SOURCES"', f'--pre-build-commands=find { sourcedir } -maxdepth 1 -name "*.bin" | cpio -H ustar -o | %e tar --show-transformed-names --transform "s;^.*/;;" -C /usr/src/packages/SOURCES -xvf -', pkgsource], cwd=builddir)
	if process.returncode != 0:
		print(f'sbuild returned { process.returncode } for { sourcedir }!')
		return False

	return True

def BuildPackages(sourcesdir, packagesdir, repodir, hostarch, signkey=None, signkeypassfile=None):
	# create working directory if missing
	if not os.path.isdir(packagesdir):
		os.mkdir(path=packagesdir)

	# create repo if missing
	if not os.path.isdir(repodir):
		os.mkdir(path=repodir)
	if not os.path.isdir(f'{ repodir }/dists'):
		os.mkdir(path=f'{ repodir }/dists')
	with tempfile.TemporaryDirectory() as emptydir:
		SendToRepo(packagesdir=emptydir, repodir=repodir, signkey=signkey, signkeypassfile=signkeypassfile)

	# spawn local http-server for the repo
	with Popen(['python3', '-m', 'http.server', '--directory', repodir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as httpd:
		# generate local repo uri
		extrarepo = f'deb [arch={ hostarch } trusted=yes] http://localhost:8000/ bullseye main'

		# foreach package (in order)
		for dir in sorted(os.listdir(sourcesdir)):
			# filter files and hidden directories
			sourcedir = f'{ sourcesdir }/{ dir }'
			if dir.startswith('.') or not os.path.isdir(sourcedir):
				continue

			# invoke build system
			print(sourcedir)
			result = BuildPackage(sourcedir=sourcedir, builddir=f'{ packagesdir }/{ dir }', hostarch=hostarch, extrarepo=extrarepo)

			# send to repo
			SendToRepo(packagesdir=f'{ packagesdir }/{ dir }', repodir=repodir, signkey=signkey, signkeypassfile=signkeypassfile)

		# kill local http-server
		httpd.terminate()

	return

def SendToRepo(packagesdir, repodir, signkey=None, signkeypassfile=None):
	# fix signkey args None for perl False
	if signkey is None:
		signkey = '0'
	if signkeypassfile is None:
		signkeypassfile = '0'

	# generate temporary debarchiver configfile
	with tempfile.NamedTemporaryFile() as configfile:
		with open('debarchiver.conf.in') as template:
			source = Template(template.read())
			result = source.substitute(dict(
				destdir = f'{ repodir }/dists',
				sourcedir = packagesdir,
				gpgkey = f'"{ signkey }"',
				gpgpassfile = f'"{ signkeypassfile }"',
			))
			configfile.write(result.encode('ascii'))
			configfile.flush()

		# let debarchiver transfer (and sign) packages
		process = subprocess.run(['debarchiver', '--configfile', configfile.name, '--index', '--rmcmd', 'true'])

		# look for rejects
		rejectdir = f'{ packagesdir }/REJECT'
		if os.path.isdir(rejectdir):
			for file in os.listdir(rejectdir):
				print(f'WARNING: debarchiver rejected { file }!')
				shutil.move(src=f'{ rejectdir }/{ file }', dst=packagesdir)
			os.rmdir(rejectdir)

###
### MAIN
###
if __name__ == "__main__":
	pwd = os.path.dirname(os.path.realpath(__file__))

	# handle cli options
	options = argparse.ArgumentParser(description='SolidRun Debian Package Builder')
	options.add_argument('-a', '--arch', action='store', required=True, help='select the target debian architecture to build for')
	options.add_argument('-c', '--collection', action='store', required=True, help='select a package collection')
	options.add_argument('-s', '--signkey', action='store', help='enable signing with a gpg key id')
	options.add_argument('-p', '--signkeypassfile', action='store', help='read signing key password from file')
	args = options.parse_args()

	# test if arch arg is valid
	archtest = subprocess.run(['dpkg-architecture', '-a', f'{ args.arch }'], stdout=subprocess.DEVNULL)
	if archtest.returncode != 0:
		print(f'Error: target architecture { args.arch } is invalid!')
		exit(1)

	# test if collection arg is valid
	collectiondir = os.path.join(pwd, 'package-recipes', args.collection)
	if not os.path.isdir(collectiondir):
		print(f'Error: { collectiondir } does not exist!')
		exit(1)
	manifestfile = os.path.join(collectiondir, 'manifest.xml')
	if not os.path.isfile(manifestfile):
		print(f'Error: { manifestfile } does not exist!')
		exit(1)
	listfile = os.path.join(collectiondir, 'download.list')

	# TODO: test if signkey arg is valid

	# test if signkeypassfile arg is valid
	if not args.signkeypassfile is None:
		if not os.path.isfile(args.signkeypassfile):
			print(f'Error: { args.signkeypassfile } does not exist!')
			exit(1)

	# create top-level build directory
	builddir = f'{ pwd }/build'
	if not os.path.isdir(builddir):
		os.mkdir(path=builddir)

	# fetch sources
	sourcesdir = os.path.join(builddir, f'sources-{ args.collection }')
	if os.path.isfile(listfile):
		FetchPackagesSourceFiles(destdir=sourcesdir, listfile=listfile)
	FetchPackagesSourceRepo(manifestrepo=pwd, destdir=sourcesdir, manifest=manifestfile)

	# build packages
	packagesdir = os.path.join(builddir, f'packages-{ args.collection }')
	repodir = os.path.join(builddir, f'repo-{ args.collection }')
	BuildPackages(sourcesdir=sourcesdir, packagesdir=packagesdir, repodir=repodir, hostarch=args.arch, signkey=args.signkey, signkeypassfile=args.signkeypassfile)

	# end
	exit(0)

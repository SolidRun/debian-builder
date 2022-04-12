#!/usr/bin/env python3
#
# Copyright 2022 Josua Mayer <josua@solid-run.com>
#

import argparse
import os
import shutil
from string import Template
import subprocess
from subprocess import Popen
import tempfile

def FetchPackagesSources(manifestrepo, destdir, manifest):
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

	if not extrarepo is None:
		process = subprocess.run(['sbuild', '--dist', 'bullseye', '--host', hostarch, '--arch-all', '-j5', f'--extra-repository={ extrarepo }', sourcedir], cwd=builddir)
	else:
		process = subprocess.run(['sbuild', '--dist', 'bullseye', '--host', hostarch, '--arch-all', '-j5', sourcedir], cwd=builddir)
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
	archtest = subprocess.run(['dpkg-architecture', '-a', f'"{ args.arch }"'])
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
	FetchPackagesSources(manifestrepo=pwd, destdir=sourcesdir, manifest=manifestfile)

	# build packages
	packagesdir = os.path.join(builddir, f'packages-{ args.collection }')
	repodir = os.path.join(builddir, f'repo-{ args.collection }')
	BuildPackages(sourcesdir=sourcesdir, packagesdir=packagesdir, repodir=repodir)

	# end
	exit(0)

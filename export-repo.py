#!/usr/bin/env python3
#
# Copyright 2022 Josua Mayer <josua@solid-run.com>
#

import os

from packages import SendToRepo

###
### MAIN
###
if __name__ == "__main__":
	pwd = os.path.dirname(os.path.realpath(__file__))

	# create target repo directory
	repodir = f'{ pwd }/export'
	if not os.path.isdir(repodir):
		os.mkdir(repodir)
	if not os.path.isdir(f'{ repodir }/dists'):
		os.mkdir(path=f'{ repodir }/dists')

	# foreach package dir (in order)
	packagesdir = f'{ pwd }/build/packages-sr-imx8-debian-11'
	for dir in sorted(os.listdir(packagesdir)):
		# add to target repo
		SendToRepo(packagesdir=f'{ packagesdir }/{ dir }', repodir=repodir, sign=True)

	exit(0)

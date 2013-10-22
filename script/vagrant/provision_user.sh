#!/bin/bash

#
# Provisioning script for the *unprivileged* user (vagrant).
#
# Tested on "precise64" (Ubuntu 12.04, 64 bit; http://files.vagrantup.com/precise64.box)
#

# Path to where Media Cloud's repository is mounted on Vagrant
MEDIACLOUD_ROOT=/mediacloud

echo "Installing Media Cloud..."
cd $MEDIACLOUD_ROOT
./install.sh

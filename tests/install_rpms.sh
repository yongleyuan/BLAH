#!/bin/bash

set -ex

BUILD_ENV=$1

# After building the RPM, try to install it
# Fix the lock file error on EL7.  /var/lock is a symlink to /var/run/lock
mkdir -p /var/run/lock

RPM_LOCATION=/tmp/rpmbuild/RPMS/x86_64
[[ $BUILD_ENV == osg ]] && extra_repos='--enablerepo=osg-upcoming-development'

package_version=`grep Version blahp/rpm/blahp.spec | awk '{print $2}'`
yum localinstall -y $RPM_LOCATION/blahp-${package_version}* $extra_repos

# Install batch systems that will exercise the blahp in osg-test
yum install -y osg-ce-condor \
    munge \
    slurm \
    slurm-slurmd \
    slurm-slurmctld \
    slurm-perlapi \
    slurm-slurmdbd \
    mariadb-server \
    mariadb  \
    torque-server \
    torque-mom \
    torque-client \
    torque-scheduler

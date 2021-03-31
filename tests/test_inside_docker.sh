#!/bin/sh -xe

OS_VERSION=$1
BUILD_ENV=$2

# Source repo version
git clone https://github.com/opensciencegrid/osg-test.git
pushd osg-test
git rev-parse HEAD
make install
popd
git clone https://github.com/opensciencegrid/osg-ca-generator.git
pushd osg-ca-generator
git rev-parse HEAD
make install
popd

# HTCondor really, really wants a domain name.  Fake one.
# PBS/Slurm really, really don't like hostnames starting with a digit
sed /etc/hosts -e "s/`hostname`/gha-`hostname`.htcondor.org gha-`hostname`/" > /etc/hosts.new
/bin/cp -f /etc/hosts.new /etc/hosts
hostname
hostname -s
python -c 'import socket; print socket.gethostbyaddr(socket.gethostname())[0]; print socket.gethostname()'

# Bind on the right interface and skip hostname checks.
cat << EOF > /etc/condor/config.d/99-local.conf
NETWORK_INTERFACE=eth0
GSI_SKIP_HOST_CHECK=true
SCHEDD_DEBUG=\$(SCHEDD_DEBUG) D_FULLDEBUG
SCHEDD_INTERVAL=1
SCHEDD_MIN_INTERVAL=1
JOB_ROUTER_POLLING_PERIOD=1
GRIDMANAGER_JOB_PROBE_INTERVAL=1
EOF
cp /etc/condor/config.d/99-local.conf /etc/condor-ce/config.d/99-local.conf

# Reduce the trace timeouts
export _condor_CONDOR_CE_TRACE_ATTEMPTS=120

# Enable PBS/Slurm BLAH debugging
mkdir /var/tmp/{qstat,slurm}_cache_vdttest/
touch /var/tmp/qstat_cache_vdttest/pbs_status.debug
touch /var/tmp/slurm_cache_vdttest/slurm_status.debug

# Ok, do actual testing
set +e # don't exit immediately if osg-test fails
echo "------------ OSG Test --------------"
osg-test -mvad --hostcert --no-cleanup
test_exit=$?
set -e

exit $test_exit

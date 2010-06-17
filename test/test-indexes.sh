#!/bin/sh -e

# Test behaviour of index retrieval and usage, in particular with uncompressed
# and gzip compressed indexes.
# Author: Martin Pitt <martin.pitt@ubuntu.com>
# (C) 2010 Canonical Ltd.

BUILDDIR=$(readlink -f $(dirname $0)/../build)

TEST_SOURCE="http://ftp.debian.org/debian unstable contrib"
GPG_KEYSERVER=gpg-keyserver.de
# should be a small package with dependencies satisfiable in TEST_SOURCE, i. e.
# ideally no depends at all
TEST_PKG="python-psyco-doc"

export LD_LIBRARY_PATH=$BUILDDIR/bin

OPTS="-o RootDir=. -o Dir::Bin::Methods=$BUILDDIR/bin/methods -o Debug::NoLocking=true"
DEBUG=""
#DEBUG="-o Debug::pkgCacheGen=true"
#DEBUG="-o Debug::pkgAcquire=true"
APT_GET="$BUILDDIR/bin/apt-get $OPTS $DEBUG"
APT_CACHE="$BUILDDIR/bin/apt-cache $OPTS $DEBUG"

[ -x "$BUILDDIR/bin/apt-get" ] || {
    echo "please build the tree first" >&2
    exit 1
}

# if $1 == "compressed", check that we have compressed indexes, otherwise
# uncompressed ones
check_indexes() {
    local F
    if [ "$1" = "compressed" ]; then
	! test -e var/lib/apt/lists/*_Packages || F=1
	! test -e var/lib/apt/lists/*_Sources || F=1
	test -e var/lib/apt/lists/*_Packages.gz || F=1
	test -e var/lib/apt/lists/*_Sources.gz || F=1
    else
	test -e var/lib/apt/lists/*_Packages || F=1
	test -e var/lib/apt/lists/*_Sources || F=1
	! test -e var/lib/apt/lists/*_Packages.gz || F=1
	! test -e var/lib/apt/lists/*_Sources.gz || F=1
    fi

    if [ -n "$F" ]; then
	ls -l var/lib/apt/lists/
	exit 1
    fi
}

echo "---- building sandbox----"
WORKDIR=$(mktemp -d)
trap "cd /; rm -rf $WORKDIR" 0 HUP INT QUIT ILL ABRT FPE SEGV PIPE TERM
cd $WORKDIR

rm -fr etc var
rm -f home
ln -s /home home
mkdir -p etc/apt/preferences.d etc/apt/trusted.gpg.d var/cache/apt/archives/partial var/lib/apt/lists/partial var/lib/dpkg
cp /etc/apt/trusted.gpg etc/apt
touch var/lib/dpkg/status
echo "deb $TEST_SOURCE" > etc/apt/sources.list
echo "deb-src $TEST_SOURCE" >> etc/apt/sources.list

echo "---- uncompressed update ----"
# first attempt should fail, no trusted GPG key
out=$($APT_GET update 2>&1)
echo "$out" | grep -q NO_PUBKEY
key=$(echo "$out" | sed -n '/NO_PUBKEY/ { s/^.*NO_PUBKEY \([[:alnum:]]\+\)$/\1/; p}')
# get keyring
gpg --no-options --no-default-keyring --secret-keyring etc/apt/secring.gpg --trustdb-name etc/apt/trustdb.gpg --keyring etc/apt/trusted.gpg --primary-keyring etc/apt/trusted.gpg --keyserver $GPG_KEYSERVER --recv-keys $key
$APT_GET update
check_indexes

echo "---- uncompressed cache ----"
$APT_CACHE show $TEST_PKG | grep -q ^Version:
# again (with cache)
$APT_CACHE show $TEST_PKG | grep -q ^Version:
rm var/cache/apt/*.bin
$APT_CACHE policy $TEST_PKG | grep -q '500 http://'
# again (with cache)
$APT_CACHE policy $TEST_PKG | grep -q '500 http://'

TEST_SRC=`$APT_CACHE show $TEST_PKG | grep ^Source: | awk '{print $2}'`
rm var/cache/apt/*.bin
$APT_CACHE showsrc $TEST_SRC | grep -q ^Binary:
# again (with cache)
$APT_CACHE showsrc $TEST_SRC | grep -q ^Binary:

echo "---- uncompressed install ----"
$APT_GET install -d $TEST_PKG 
test -e var/cache/apt/archives/$TEST_PKG*.deb
$APT_GET clean
! test -e var/cache/apt/archives/$TEST_PKG*.deb

echo "---- uncompressed get source ----"
$APT_GET source $TEST_PKG
test -f $TEST_SRC_*.dsc
test -d $TEST_SRC-*
rm -r $TEST_SRC*

echo "----- uncompressed update with preexisting indexes, no pdiff ----"
$APT_GET -o Acquire::PDiffs=false update
check_indexes

echo "----- uncompressed update with preexisting indexes, with pdiff ----"
$APT_GET -o Acquire::PDiffs=true update
check_indexes

echo "----- compressed update ----"
find var/lib/apt/lists/ -type f | xargs -r rm
$APT_GET -o Acquire::GzipIndexes=true update
check_indexes compressed

echo "---- compressed cache ----"
$APT_CACHE show $TEST_PKG | grep -q ^Version:
# again (with cache)
$APT_CACHE show $TEST_PKG | grep -q ^Version:
rm var/cache/apt/*.bin
$APT_CACHE policy $TEST_PKG | grep -q '500 http://'
# again (with cache)
$APT_CACHE policy $TEST_PKG | grep -q '500 http://'

TEST_SRC=`$APT_CACHE show $TEST_PKG | grep ^Source: | awk '{print $2}'`
rm var/cache/apt/*.bin
$APT_CACHE showsrc $TEST_SRC | grep -q ^Binary:
# again (with cache)
$APT_CACHE showsrc $TEST_SRC | grep -q ^Binary:

echo "---- compressed install ----"
$APT_GET install -d $TEST_PKG 
! test -e var/cache/apt/archives/$TEST_PKG*.deb

echo "---- compressed get source ----"
$APT_GET source $TEST_PKG
test -f $TEST_SRC_*.dsc
test -d $TEST_SRC-*
rm -r $TEST_SRC*

echo "----- compressed update with preexisting indexes, no pdiff ----"
$APT_GET -o Acquire::PDiffs=false -o Acquire::GzipIndexes=true update
check_indexes compressed

echo "----- compressed update with preexisting indexes, with pdiff ----"
$APT_GET -o Acquire::PDiffs=true -o Acquire::GzipIndexes=true update
check_indexes compressed

echo "---- ALL TESTS PASSED ----"

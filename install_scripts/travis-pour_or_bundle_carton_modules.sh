#!/bin/bash
#
# Either:
# 1) download Carton dependencies bundle from S3 and extract it as "local/", or
# 2) build the Carton dependencies, bundle them and upload to S3
#
# Links:
# * http://blog.travis-ci.com/2012-12-18-travis-artifacts/
#

set -e
set -u
set -o errexit

S3_REGION="us-east-1"
S3_BUCKET_NAME="travis-ci-cache-mediacloud-pypt-lt"
S3_PATH="carton-bundles"
S3_PREFIX="local"

# ---

function bundle_id {

    # Kernel architecture, e.g. x86_64
    local OS_ARCH=`uname -m`

    # Perl version, e.g. 5.016002
    local PERL_VERSION=`perl -e "print $]"`

    # Author date (GMT) of current version of "cpanfile", e.g. "2014_06_23_15_29_22"
    local CPANFILE_SHA1=$(TZ=UTC date -r $(git log -1 --format=%at cpanfile) "+%F-%T" | tr -s ' :-' '_')

    # Author date (GMT) of current version of "cpanfile.snapshot", e.g. "2014_06_23_14_50_51"
    local CPANFILE_SNAPSHOT_SHA1=$(TZ=UTC date -r $(git log -1 --format=%at cpanfile.snapshot) "+%F-%T" | tr -s ' :-' '_')

    # OS version
    local OS_VERSION="unknown"
    if [ -f /etc/lsb-release ]; then
        source /etc/lsb-release
        OS_VERSION="ubuntu_$DISTRIB_RELEASE"
    elif [ `uname` == 'Darwin' ]; then
        MAC_OS_X_VERSION=`sw_vers -productVersion`
        OS_VERSION="osx_${MAC_OS_X_VERSION}"
    fi

    local BUNDLE_ID="${OS_VERSION}-${OS_ARCH}-perl_${PERL_VERSION}-cpanfile_${CPANFILE_SHA1}-snapshot_${CPANFILE_SNAPSHOT_SHA1}"
    echo "$BUNDLE_ID"
}

# 'cd' to Media Cloud's root (assuming that this script is stored in './install_scripts/')
PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$PWD/../"

if [ ! -d .git ]; then
    echo ".git directory doesn't exist in the current path."
    echo "Either you didn't checkout Media Cloud from the GitHub repository, or you're not in the Media Cloud root path."
    exit 1
fi

BUNDLE_ID=`bundle_id`
echo "Bundle ID: $BUNDLE_ID"

TGZ_FILENAME="${S3_PREFIX}-${BUNDLE_ID}.tgz"
echo "TGZ filename: $TGZ_FILENAME"

BUNDLE_URL="http://${S3_BUCKET_NAME}.s3-website-${S3_REGION}.amazonaws.com/${S3_PATH}/${TGZ_FILENAME}"
echo "Bundle URL: $BUNDLE_URL"

if curl --output /dev/null --silent --head --fail "$BUNDLE_URL" > /dev/null; then

    echo "Bundle at URL exists, fetching and pouring..."
    curl -0 "$BUNDLE_URL" | tar -zx || {
        echo "Bundle exists at the URL, but I've failed to download and pour it, so giving up."
        exit 1
    }

else
    echo "Bundle at URL doesn't exist, building..."
    ./install_modules_with_carton.sh

    echo "Dependencies were build, archiving..."
    tar -czf "$TGZ_FILENAME" local/

    echo "Uploading to S3..."
    travis-artifacts upload \
        --path "$TGZ_FILENAME" \
        --target-path "$S3_PATH/"

    echo "Removing archive..."
    rm "$TGZ_FILENAME"

fi

echo "Done."

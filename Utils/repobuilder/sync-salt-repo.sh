#!//bin/bash
__SCRIPTNAME="sync-salt-repo.sh"

set -eu
set -x

exec > >(logger -i -t "${__SCRIPTNAME}" -s 2> /dev/console) 2>&1

# User vars
BUCKET_NAME="${1}"
BUCKET_KEY="${2}"  # E.g. "linux/saltstack/salt"
SALT_VERSION="${3}"
SALT_REPO="${4:-rsync://repo.saltstack.com/saltstack_pkgrepo_rhel}"

# Internal vars
BASE_URL="https://s3.amazonaws.com/${BUCKET_NAME}/${BUCKET_KEY}"  # Common http path for the hosted packages
STAGING="/root/${BUCKET_NAME}/${BUCKET_KEY}"
REPOS=(
    "SALT_AMAZON"
    "SALT_REDHAT_EL6"
    "SALT_REDHAT_EL7"
)
YUM_FILE_DIR="${STAGING}/yum.repos"  # Where do we want to save the yum repo files?

# amzn repo vars
REPO_NAME_SALT_AMAZON="${BUCKET_NAME}-salt-amzn"
REPO_BASEURL_SALT_AMAZON="${BASE_URL}/amazon/latest/\$basearch/archive/${SALT_VERSION}"
REPO_GPGKEY_SALT_AMAZON="${BASE_URL}/amazon/latest/\$basearch/archive/${SALT_VERSION}/SALTSTACK-GPG-KEY.pub"

# el6 repo vars
REPO_NAME_SALT_EL6="${BUCKET_NAME}-salt-el6"
REPO_BASEURL_SALT_EL6="${BASE_URL}/redhat/6/\$basearch/archive/${SALT_VERSION}"
REPO_GPGKEY_SALT_EL6="${BASE_URL}/redhat/6/\$basearch/archive/${SALT_VERSION}/SALTSTACK-GPG-KEY.pub"

# el7 repo vars
REPO_NAME_SALT_EL7="${BUCKET_NAME}-salt-el7"
REPO_BASEURL_SALT_EL7="${BASE_URL}/redhat/7/\$basearch/archive/${SALT_VERSION}"
REPO_GPGKEY_SALT_EL7="${BASE_URL}/redhat/7/\$basearch/archive/${SALT_VERSION}/SALTSTACK-GPG-KEY.pub"

_rsync_include_salt_versions()
{
    local versions
    local rsync_include
    versions="$1"
    rsync_include=""
    for version in ${versions}
    do
      rsync_include="${rsync_include}--include \"*/${version}/**\" "
    done
    echo "${rsync_include}"
}

__print_repo_file() {
    # Function that prints out a yum repo file
    if [ $# -eq 3 ]; then
        name=$1
        baseurl=$2
        gpgkey=$3
    else
        printf "ERROR: __print_repo_file requires three arguments." 1>&2;
        exit 1
    fi
    printf "[%s]\n" "${name}"
    printf "name=%s\n" "${name}"
    printf "baseurl=%s\n" "${baseurl}"
    printf "gpgcheck=1\n"
    printf "gpgkey=%s\n" "${gpgkey}"
    printf "enabled=1\n"
    printf "skip_if_unavailable=1\n"
}

echo "${__SCRIPTNAME} starting!"

# Pull salt repos
rsync -vazH -m --no-links --numeric-ids --delete --delete-after --delay-updates \
    --exclude "*/SRPMS*" \
    --exclude "*/i386*" \
    --exclude "redhat/5*" \
    --include "*/" \
    --include "*/${SALT_VERSION}/**" \
    # $(_rsync_include_salt_versions $SALT_VERSIONS) \
    --exclude "*" \
    "$SALT_REPO" "${STAGING}"

# Create repo files
mkdir -p "${YUM_FILE_DIR}"
for repo in "${REPOS[@]}"; do
    repo_name="REPO_NAME_${repo}"
    repo_baseurl="REPO_BASEURL_${repo}"
    repo_gpgkey="REPO_GPGKEY_${repo}"
    __print_repo_file "${!repo_name}" "${!repo_baseurl}" "${!repo_gpgkey}" \
        > "${YUM_FILE_DIR}/${!repo_name}.repo"
done

# Push salt repos
cd "${STAGING}"
aws s3 sync --delete . "s3://${BUCKET_NAME}/${BUCKET_KEY}"

echo "${__SCRIPTNAME} done!"

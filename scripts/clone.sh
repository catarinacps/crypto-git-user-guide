#!/bin/sh

# author: @hcpsilva

# crashes if an error occurs
set -euf

usage() {
    cat <<EOF
  $0 [OPTIONS] <URI>

  WHERE [OPTIONS] can be any of the following, in no particular order:
    -h | --help
      shows this message and quits
    -p | --prefix <PATH>
      uses a custom prefix instead of the default $HOME
    -d | --directory <PATH>
      uses a custom directory instead of the default repo name
    -v | --verbose
      be verbose
    -f | --force
      overwrite any existing ecryptfs private directory
      PLEASE BACKUP YOUR DATA BEFORE DOING THIS

  WHERE <URI> is the URI of your existing repo, ssh format, e.g.:
    \"git@server:/srv/git/repo.git\"
EOF
}

for arg; do
    case $arg in
        -h|--help)
            echo "USAGE:"
            usage
            exit
            ;;
        -p|--prefix)
            shift
            PREFIX="$1"
            shift
            ;;
        -d|--directory)
            shift
            GIT_DIR="$1"
            shift
            ;;
        -v|--verbose)
            VERBOSE='true'
            shift
            ;;
        -f|--force)
            FORCE='true'
            shift
            ;;
        -*)
            echo "ERROR: unknown option '$arg'"
            echo
            echo "USAGE:"
            usage
            exit 1
            ;;
    esac
done

# prefix directory
PREFIX=${PREFIX:-$HOME}

# verbose flag
VERBOSE=${VERBOSE:-'false'}

# forceful flag
FORCE=${FORCE:-'false'}

# the URI of your existing repo
if [ -z "$1" ]; then
    echo "ERROR: missing positional argument <URI>"
    echo
    echo "USAGE:"
    usage
    exit 2
else
    GIT_URI=$1
fi

if [ ! -x "$(command -v ecryptfs-mount-private)" ]; then
    echo "ERROR: the necessary ecryptfs tooling isn't available"
    echo "  please install 'ecryptfs-utils'"
    exit 3
fi

if [ ! -x "$(command -v git)" ]; then
    echo "ERROR: git isn't available"
    echo "  please install 'git'"
    exit 3
fi

if [ -d "$HOME/.Private" ] && [ $FORCE = 'false' ]; then
    echo "ERROR: You have already configured a private directory with ecryptfs"
    echo "  consider using the '-f' flag to overwrite this directory"
    echo "  PLEASE BACKUP YOUR DATA BEFORE DOING THIS"
    exit 4
elif [ $FORCE = 'true' ]; then
    echo "PLEASE CONFIRM YOUR CHOICE"

    confirmation=""
    while [ $confirmation != 'y' ] || [ $confirmation != 'n']; do
        read -p "Please type y or n: " confirmation
    done

    if [ $confirmation = 'n' ]; then
        echo "INFO: canceling operation..."
        exit 0
    fi

    ecryptfs-umount-private
    PDIR="$(cat $HOME/.ecryptfs/Private.mnt)"
    rm -rf $HOME/.Private $HOME/.ecryptfs $PDIR
fi

# final git directory
GIT_DIR=$PREFIX/${GIT_DIR:-$(basename $GIT_URI .git)}

# creating the private encripted folder
ecryptfs-setup-private --nopwcheck --noautomount

# move to a better name
mv $HOME/Private $GIT_DIR
echo $(readlink -f $GIT_DIR) > $HOME/.ecryptfs/Private.mnt

# mount the directory
ecryptfs-mount-private

# init and pull the repo
cd $GIT_DIR
git init
git remote add origin gcrypt::$GIT_URI
git pull origin master --allow-unrelated-histories

# done
[ $VERBOSE = 'true' ] && echo "INFO: success!"

exit

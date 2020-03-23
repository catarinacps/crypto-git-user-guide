#!/bin/bash

# author: @hcpsilva

# crashes if an error occurs
set -euf -o pipefail

# color and formatting codes using tput
BOLD=$(tput bold)
UNDLN=$(tput smul)
STOUT=$(tput smso)
RESET=$(tput sgr0)


# functions

function usage() {
    cat <<EOF
  $0 [OPTIONS] <URI>

  ${BOLD}WHERE${RESET} [OPTIONS] can be any of the following, ${UNDLN}in no particular order${RESET}:
    -h | --help
      shows this message and quits
    -n | --dir-name <PATH>
      uses a custom directory instead of the default repo name
    -q | --quiet
      be quiet(er)
    -e | --encrypt
      encrypt the repository directory with ecryptfs
    -f | --force
      overwrite any existing ecryptfs private directory
      ${UNDLN}PLEASE BACKUP YOUR DATA BEFORE DOING THIS${RESET}
    -d | --dry
      runs in dry mode (print everything) and doesn't do anything besides that

  ${BOLD}WHERE${RESET} <URI> is the URI of your existing repo, ssh format, e.g.:
    "git@server:/srv/git/repo.git"
EOF
}

function verbose_echo() {
    [ $VERBOSE = 'true' ] && echo -e $*
}

function select_collaborators() {
    verbose_echo "\n-> ${BOLD}Select the desired keys${RESET}" 1>&2
    verbose_echo '--> Available public keys in your GnuPG keyring:\n' 1>&2

    PUB_KEYS=($(gpg -k --keyid-format long | grep '^pub' | awk '{print $2}' | cut -d'/' -f2 | xargs))
    IFS=$'\n' UID_KEYS=($(gpg -k --keyid-format long | sed -n '/^pub/{n;n;p;}' | cut -d']' -f2- | cut -d' ' -f2-))

    while [ -z "${CHOSEN_KEYS:-}" ]; do
        local counter=0
        for kuid in "${UID_KEYS[@]}"; do
            echo -e "INDEX ${UNDLN}${counter}${RESET}:\n  $kuid\n" 1>&2
            (( counter = counter + 1 ))
        done

        echo 1>&2

        read -p "Insert the ${UNDLN}INDEXES${RESET} listed above (separated by spaces): " idxs

        local IFS=' '
        for id in "$idxs"; do
            CHOSEN_KEYS="${PUB_KEYS[$id]} ${CHOSEN_KEYS:-}"
        done

        if [ -z "${CHOSEN_KEYS:-}" ]; then
            echo -e "\n--> ${BOLD}ERROR${RESET}: no keys were chosen!\n" 1>&2
            exit 5
        fi
    done

    echo "$CHOSEN_KEYS"
}

function setup_directory() {
    [ ! -z ${1+z} ] && DIR_NAME=$1 || exit 1

    if [ ! -x "$(command -v ecryptfs-mount-private)" ]; then
        echo "${BOLD}ERROR${RESET}: the necessary ecryptfs tooling isn't available"
        echo "  please install 'ecryptfs-utils'"
        exit 2
    fi

    if [ -d "$HOME/.Private" ] && [ "$FORCE" = 'false' ]; then
        echo "${BOLD}ERROR${RESET}: You have already configured a private directory with ecryptfs"
        echo "  consider using the '-f' flag to overwrite this directory"
        echo "  and ${BOLD}PLEASE BACKUP YOUR DATA BEFORE DOING THIS${RESET}"
        exit 4
    elif [ "$FORCE" = 'true' ]; then
        echo "--> ${BOLD}CONFIRM YOUR CHOICE${RESET}"

        input=''
        while [ "$input" != 'y' ] && [ "$input" != 'n' ]; do
            read -p "---> Please type y or n: " input
        done

        [ "$input" = 'n' ] && echo -e "---> ${BOLD}INFO${BOLD}: operation canceled..." && exit 0

        verbose_echo "---> Unmounting current directory"
        $DRY ecryptfs-umount-private
        PDIR="$(cat $HOME/.ecryptfs/Private.mnt)"
        verbose_echo "---> Deleting previous config (you need root to do this)"
        $DRY sudo rm -rf $HOME/.Private $HOME/.ecryptfs $PDIR
        verbose_echo
    fi

    # creating the private encripted folder
    verbose_echo "--> ${BOLD}Setting up the directory with ecryptfs${RESET}\n"
    $DRY ecryptfs-setup-private --nopwcheck --noautomount

    # move to a better name
    verbose_echo "--> Changing the default name"
    $DRY mv $HOME/Private $GIT_DIR
    [ -z "$DRY" ] && echo $(readlink -f $GIT_DIR) > $HOME/.ecryptfs/Private.mnt

    # mount the directory
    verbose_echo "--> Mounting the volume"
    $DRY ecryptfs-mount-private

    echo
}


# parameter parsing

for arg; do
    case $arg in
        -h|--help)
            echo "${BOLD}USAGE${RESET}:"
            usage
            exit
            ;;
        -d|--dry)
            DRY='echo'
            shift
            ;;
        -n|--dir-name)
            shift
            GIT_DIR="$1"
            shift
            ;;
        -q|--quiet)
            VERBOSE='false'
            shift
            ;;
        -f|--force)
            FORCE='true'
            shift
            ;;
        -e|--encrypt)
            ENCRYPT='true'
            shift
            ;;
        -*)
            echo "${BOLD}ERROR${RESET}: unknown option '$arg'"
            echo
            echo "${BOLD}USAGE${RESET}:"
            usage
            exit 1
            ;;
    esac
done


# default variables

# verbose flag
VERBOSE=${VERBOSE:-'true'}

# forceful flag
FORCE=${FORCE:-'false'}

# dry mode
DRY=${DRY:-''}

# encrypt the repo dir with ecryptfs
ENCRYPT=${ENCRYPT:-'false'}


# start of the script

verbose_echo "----- CRYPTO-GIT ---------------------------------"

# the URI of your existing repo
if [ -z "${1:+z}" ]; then
    echo "${BOLD}ERROR${RESET}: missing positional argument <URI>"
    echo
    echo "${BOLD}USAGE${RESET}:"
    usage
    exit 2
else
    GIT_URI=$1
fi

if [ ! -x "$(command -v git)" ]; then
    echo "${BOLD}ERROR${RESET}: git isn't available"
    echo "  please install 'git'"
    exit 3
fi

# final git directory
GIT_DIR="$HOME/${GIT_DIR:-$(basename $GIT_URI .git)}"

verbose_echo "\n-> Creating directory"
[ "$ENCRYPT" = 'true' ] && setup_directory "$GIT_DIR" || $DRY mkdir "$GIT_DIR"

# init and pull the repo
verbose_echo "\n-> ${BOLD}Initializing the repository${RESET}"
$DRY cd "$GIT_DIR"
$DRY git init
$DRY git remote add origin "gcrypt::$GIT_URI"

# add a hook so we ALWAYS pull before pushing
[ -z "$DRY" ] && cat << 'EOF' > "$GIT_DIR/.git/hooks/pre-push"
#!/bin/sh

set -euf

echo "pulling..."
git fetch --all
git pull

PARTICIPANTS="$(git config --get remote.origin.gcrypt-participants)"

if [ -z "$PARTICIPANTS" ]; then
    echo "missing participants!"
    echo "please set the 'remote.origin.gcrypt-participants' variable in git config"
    exit 1
fi
EOF

KEYS="$(select_collaborators)"

verbose_echo "\n-> ${BOLD}Adding selected participants${RESET}"
$DRY git config remote.origin.gcrypt-participants "$KEYS"

verbose_echo "\n-> Updating the repository"
$DRY git fetch --all
$DRY git pull origin master --allow-unrelated-histories

# done
verbose_echo "\n\n${BOLD}INFO${RESET}: success!"

exit

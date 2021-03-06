#!/bin/bash
################################################################################
### SocialSend MASTERNODE INSTALLATION SCRIPT v1.2.0
################################################################################


declare -r SSH_INBOUND_PORT=22
declare -r AUTODETECT_EXTERNAL_IP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | head -n 1`

declare -r MN_SWAPSIZE=2000
declare    MN_USER="send"
declare -r MN_DAEMON=/usr/local/bin/sendd
declare -r MN_INBOUND_PORT=50050            #mainnet
#declare -r MN_INBOUND_PORT=51474           #testnet
declare    MN_CONF_DIR=/home/${MN_USER}/.send
declare    MN_CONF_FILE=${MN_CONF_DIR}/send.conf
declare -r MN_RPCUSER=$(date +%s | sha256sum | base64 | head -c 10 ; echo)
declare -r MN_RPCPASS=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`

declare -r DATE_STAMP="$(date +%y-%m-%d-%s)"
declare -r SCRIPTPATH=$( cd $(dirname ${BASH_SOURCE[0]}) > /dev/null; pwd -P )
declare -r MASTERPATH="$(dirname "${SCRIPTPATH}")"
declare -r SCRIPT_VERSION="v1.2.0"
declare -r SCRIPT_LOGFILE="/tmp/send_mn_setup_${DATE_STAMP}.log"

declare -r GIT_URL=https://github.com/SocialSend/SocialSend.git
declare -r RELEASE_VERSION_SRC="master"     #mainnet
#declare -r RELEASE_VERSION_SRC="Dev"       #testnet
declare -r CODE_DIR="SocialSend"

declare -r RELEASE_VERSION="1.2.0"
declare -r RELEASE_BUILD=1

EXTERNAL_IP=${AUTODETECT_EXTERNAL_IP}


function output() {
    printf "$(tput bold)$(tput setab 0)$(tput setaf 7)"
    echo $1
    printf "$(tput sgr0)"
}

function displayError() {
    echo
    echo $1;
    echo
    exit 1;
}

function get_confirmation() {
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}

function get_user() {
    read -r -p "Is your masternode running as 'send' user? [y/n] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            read -e -p "Enter the user: " MN_USER
            MN_CONF_DIR=/home/${MN_USER}/.send

            if [ ${MN_USER} = "root" ]; then
                MN_CONF_DIR=/root/.send
            fi

            MN_CONF_FILE=${MN_CONF_DIR}/send.conf
            false
            ;;
    esac
}

function add_firewal_rule() {
    output ""
    output "Adding new firewall rule"
    sudo ufw allow ${MN_INBOUND_PORT}/tcp       &>> ${SCRIPT_LOGFILE}
}

function unpack_bootstrap() {
    output ""
    output "Stopping SEND daemon..."
    sudo killall sendd &>> ${SCRIPT_LOGFILE}

    cd $MN_CONF_DIR &>> ${SCRIPT_LOGFILE}
    rm -R blocks/ &>> ${SCRIPT_LOGFILE}
    rm -R chainstate/ &>> ${SCRIPT_LOGFILE}
    rm -R peers.dat &>> ${SCRIPT_LOGFILE}
    
    output "Downloading bootstrap.."
    wget https://www.dropbox.com/s/rxzq0ofafh0dfpb/bootstrap.zip?dl=0 -O bootstrap.zip &>> ${SCRIPT_LOGFILE}

    output "Unpacking bootstrap"
    unzip bootstrap.zip &>> ${SCRIPT_LOGFILE}
    sudo chown -R ${MN_USER}:${MN_USER} ${MN_CONF_DIR} &>> ${SCRIPT_LOGFILE}
    rm -rf bootstrap.zip &>> ${SCRIPT_LOGFILE}
}


function launch_daemon() {
    output ""
    output "Launching daemon..."

    sudo -u ${MN_USER} -H sendd &>> ${SCRIPT_LOGFILE}
}


function finish() {
    output ""
    output "Success! Your SocialSend masternode has been updated"
    exit 0
}



clear
#add_firewal_rule
get_user
unpack_bootstrap
launch_daemon
finish
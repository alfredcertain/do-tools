#!/usr/bin/env bash

set -o errexit
set -o nounset
set -euo pipefail

function log {
    local now=$(date +'%Y-%m-%d %H:%M:%S')
    echo "$1"
    echo "[$now] $1" >> cmd-do-provision.log
}

function create_droplet {
    doctl compute droplet create "$1" --wait --size "$2" --image "$3" --region "$4" --ssh-keys "$5" --tag-names "$6" --enable-monitoring --enable-private-networking
}

function create_volume {
    doctl compute volume create "$1" --region "$2" --size "$3" --desc "Volume for $1"
}

function attach_volume_to_droplet {
    local volume=$(doctl compute volume list | grep "$1" | awk '{ print $1 }')
    local droplet=$(doctl compute droplet list | grep "$2" | awk '{ print $1 }')
    doctl compute volume-action attach "$volume" "$droplet"
}

function create_firewall {
    local fw_name=$1"-fw"
    local droplet=$(doctl compute droplet list | grep "$1" | awk '{ print $1 }')
    doctl compute firewall create --name "$fw_name" --inbound-rules protocol:tcp,ports:22
}

function add_droplet_to_firewall {
    local firewall=$(doctl compute firewall list | grep "$1" | awk '{ print $1 }')
    local droplet=$(doctl compute droplet list | grep "$2" | awk '{ print $1 }')
    doctl compute firewall add-droplets "$firewall" --droplet-ids "$droplet"
}

function add_rule_to_firewall {
    local firewall=$(doctl compute firewall list | grep "$1" | awk '{ print $1 }')
    local droplet=$(doctl compute droplet list | grep "$1" | awk '{ print $1 }')
    local fw_protocol=$2
    local fw_port=$3
    echo "doctl compute firewall add-rules $firewall --inbound-rules protocol:$fw_protocol,ports:$fw_port"
    doctl compute firewall add-rules "$firewall" --inbound-rules protocol:"$fw_protocol",ports:"$fw_port"
}

function add_rule_to_firewall_sdroplet {
    local firewall=$(doctl compute firewall list | grep "$1" | awk '{ print $1 }')
    local fw_protocol=$2
    local fw_port=$3
    local sdroplet=$(doctl compute droplet list | grep -E "\b$4(\s|$)" | awk '{ print $1 }')
    echo "doctl compute firewall add-rules $firewall --inbound-rules protocol:$fw_protocol,ports:$fw_port,droplet_id:$sdroplet"
    doctl compute firewall add-rules "$firewall" --inbound-rules protocol:"$fw_protocol",ports:"$fw_port",droplet_id:"$sdroplet"
}

function add_rule_to_firewall_saddress {
    local firewall=$(doctl compute firewall list | grep "$1" | awk '{ print $1 }')
    local fw_protocol=$2
    local fw_port=$3
    local saddress=$4
    echo "doctl compute firewall add-rules $firewall --inbound-rules protocol:$fw_protocol,ports:$fw_port,address:$saddress"
    doctl compute firewall add-rules "$firewall" --inbound-rules protocol:"$fw_protocol",ports:"$fw_port",address:"$saddress"
}

function delete_droplet {
    echo "doctl compute droplet delete --force $1"
}

function delete_volume {
    echo "doctl compute volume delete $1"
}

function delete_firewall {
    echo "doctl compute firewall delete $1"
}

DROPLET_SIZE="s-1vcpu-1gb-intel"
VOLUME_SIZE="25GiB"
SSHKEY_NAME="MyName"
DROPLET_IMAGE=$(doctl compute image list --public | grep "20-04-x64" | awk '{ print $1 }')
DROPLET_REGION="nyc3"
DROPLET_SSHKEY=$(doctl compute ssh-key list | grep "$SSHKEY_NAME" | awk '{ print $1 }')

case "$1" in
    install)

    read -p "- Droplet Name: [single word] ? " DROPLET_NAME

    DROPLET_TAG=$DROPLET_NAME"

    # Create Resources for Droplet
    log "Creating $DROPLET_NAME droplet in $DROPLET_REGION tagged with $DROPLET_TAG"
    create_droplet "$DROPLET_NAME" "$DROPLET_SIZE" "$DROPLET_IMAGE" "$DROPLET_REGION" "$DROPLET_SSHKEY" "$DROPLET_TAG"
    
    log "Creating Volume for $DROPLET_NAME"
    create_volume "$DROPLET_NAME-vol" $DROPLET_REGION "$VOLUME_SIZE"
            
    log "Attaching Volume for $DROPLET_NAME"
    attach_volume_to_droplet "$DROPLET_NAME-vol" "$DROPLET_NAME"

    # Create Firewall resources
    DROPLET_PUBLIC_IP=$(doctl compute droplet list | grep "$DROPLET_NAME" | awk '{ print $3 }')
    DROPLET_PRIVATE_IP=$(doctl compute droplet list | grep "$DROPLET_NAME" | awk '{ print $4 }')

    log "Creating Firewall for $DROPLET_NAME"
    create_firewall "$DROPLET_NAME"
    sleep 5
    add_droplet_to_firewall "$DROPLET_NAME-fw" "$DROPLET_NAME"

    log "Adding standard rules to Firewall for droplet $DROPLET_NAME"
    add_rule_to_firewall "$DROPLET_NAME-fw" "tcp" "80"
    add_rule_to_firewall "$DROPLET_NAME-fw" "tcp" "443"

    ;;
    uninstall)

    read -p "- Droplet Name: [single word] ? " DROPLET_NAME

    DROPLET_TAG=$DROPLET_NAME

    echo "DELETING ALL droplets and volumes for tag: $DROPLET_TAG"
    for droplet in $(doctl compute droplet list | grep "$DROPLET_TAG" | awk '{ print $1 }'); do
        echo "DROPLET: $droplet"
    done;
    for volume in $(doctl compute volume list | grep "$CUSTOMER" | awk '{ print $1 }'); do
        echo "VOLUME: $volume"
    done;

    read -p "Are you sure? [Y/N]" -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        log "Deleting all Droplets tagged with $DROPLET_TAG"
        for droplet in $(doctl compute droplet list | grep "$DROPLET_TAG" | awk '{ print $1 }'); do
            log "Deleting Droplet $droplet"
            delete_droplet "$droplet";
        done;

        log "Deleting all Volumes with $DROPLET_NAME in their name"
        for volume in $(doctl compute volume list | grep "$DROPLET_NAME-vol" | awk '{ print $1 }'); do
            log "Deleting Volume $volume"
            delete_volume "$volume";
        done;

        log "Deleting all Firewalls with $DROPLET_NAME in their name"
        for firewall in $(doctl compute firewall list | grep "$DROPLET_NAME-fw" | awk '{ print $1 }'); do
            log "Deleting Firewall $firewall"
            delete_firewall "$firewall";
        done;
    fi
    
;;
    *)
        echo "Usage: do-cmd-provision {install|uninstall}" >&2
        exit 3
    ;;
esac

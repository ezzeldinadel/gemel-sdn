#!/usr/bin/env bash

# get directory of current file
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# load globals
. $DIR/import.sh

print_help() {
    echo "Usage: ./set-vn.sh -i [VM INSTANCE NAME IN GCP] -n [VN NAME]"
}

if [ $# -eq 0 ]
then
    print_help
    exit 0
fi

while getopts "h?i:n:f:" opt; do
    case "$opt" in
    h|\?)
        print_help
        exit 0
        ;;
    i)  gcp_name=$OPTARG
        ;;
    n)  vn_name=$OPTARG
        ;;
    esac
done

if [[ -z "$gcp_name" || -z "$vn_name" ]]
then
    echo "VM and VN names should be specified"
    exit 1
fi

log "Adding host $gcp_name to VN $vn_name"

log "Pinging to let controller know we exist"
host_mac=$(gcloud compute ssh $gcp_name -- ping -c5 210.0.0.101)

host_mac=$(gcloud compute ssh $gcp_name -- bash -c 'ifconfig | grep br0 | grep -oE "(.{2}:){5}.{2}"')

host_mac=$(echo -n $host_mac | sed 's/\\r//g')
host_mac="${host_mac/$'\r'/}"

log "VM MAC address is $host_mac"

switch_ip=$(gcloud compute ssh $gcp_name -- sudo ovs-vsctl show | grep -oE 'remote_ip=".+"' | grep -oE '([0-9]+\.){3}[0-9]+')

log "switch IP is \"$switch_ip\""

vxlan_key=$(gcloud compute ssh $gcp_name -- sudo ovs-vsctl show | grep -oE 'key="[0-9]+"' | grep -oE '[0-9]+')

log "VXLAN key is $vxlan_key"

switch_gcp_name=$(gcloud compute instances list | grep -E "$switch_ip" | awk '{print $1}')

log "switch VM name is \"$switch_gcp_name\""

# find associated port on switch
switch_port=$(gcloud compute ssh $switch_gcp_name -- sudo ovs-vsctl show | grep -B 1000 "key=\"$vxlan_key\"" | grep -oE 'Port ".+"' | tail -n 1 | grep -oE '".+"' | cut -d"\"" -f2)

log "VM ingress port is interface \"$switch_port\" @ $switch_gcp_name"

# call topology API to find openflow ID of switch
bash $DIR/get_topology.sh

# extract openflow ID of switch from topology API results
ids="$(python "$DIR/get_id.py" "$DIR/out.xml" "$host_mac")"
switch_id=$(echo "$ids" | tail -n 1)

log "OpenFlow ID of the switch is $switch_id"

bridge_name=$(curl --user "$ODL_API_USER":"$ODL_API_PASS" -X GET $ODL_API_URL/restconf/operational/vtn:vtns/ | jq -r ".vtns | .[] | .[] | select(.name==\"$vn_name\") | .vbridge | .[0] | .name")

log "Bridge on $vn_name is called: $bridge_name"

interface_num=$(( $( curl --user "$ODL_API_USER":"$ODL_API_PASS" -X GET $ODL_API_URL/restconf/operational/vtn:vtns/ | jq -r ".vtns | .[] | .[] | select(.name==\"$vn_name\") | .vbridge | .[0] | .vinterface | .[] | .name" | sed -E 's/^[[:alnum:]]+i([[:digit:]]+)$/\1/g' | sort -n | tail -n 1 ) + 1 ))

iface_name="${vn_name}i$interface_num"

log "New interface will be called $iface_name"

# create new interface
curl --fail --user "$ODL_API_USER":"$ODL_API_PASS" -H "Content-type: application/json" -X POST \
    $ODL_API_URL/restconf/operations/vtn-vinterface:update-vinterface \
    -d "{\"input\":{\"tenant-name\":\"$vn_name\", \"bridge-name\":\"$bridge_name\", \"interface-name\":\"$iface_name\"}}" \
    || exit 1

echo

log "iface $iface_name created."

# trigger final API call
curl --fail --user "$ODL_API_USER":"$ODL_API_PASS" -H "Content-type: application/json" -X POST \
    "$ODL_API_URL/restconf/operations/vtn-port-map:set-port-map" \
    -d "{\"input\":{\"tenant-name\":\"$vn_name\", \"bridge-name\":\"$bridge_name\", \"interface-name\":\"$iface_name\", \"node\":\"$switch_id\", \"port-name\":\"$switch_port\"}}" \
    || exit 1

echo

log Success!

#!/bin/bash

usage(){
    echo "./install.sh [hostname] [management console pass]"
    exit 1
}

flatten(){
    cat ${1} | perl -pe 's/\n/\\n/g'
}

main(){
    local HOST=${1}
    local PASS=${2}
    [ -z "${HOST}" ] && usage
    [ -z "${PASS}" ] && usage

    local CRT="./domains/${HOST}/cert.pem"
    local KEY="./domains/${HOST}/key.pem"
    [ -f "${CRT}" ] || { echo "${CRT} is missing"; exit 1; }
    [ -f "${KEY}" ] || { echo "${KEY} is missing"; exit 1; }

    local URL="https://api_key:${PASS}@${HOST}:8443/setup/api"
    local JSON="{\"github_ssl\":{\"enabled\":\"true\",\"cert\":\"$(flatten ${CRT})\",\"key\":\"$(flatten ${KEY})\"}}"

    curl -k -L -X PUT "${URL}/settings" --data-urlencode "settings=${JSON}"
    curl -k -L -X POST "${URL}/configure"
}

main $@

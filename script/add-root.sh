#!/bin/bash

usage(){
	echo "./add_root.sh [hostname]"
	exit 1
}

HOST=${1}
[ -z "${HOST}" ] && usage

scp -P 122 demoCA/cacert.pem admin@${HOST}:/home/admin
ssh -p 122 admin@${HOST} "ghe-ssl-ca-certificate-install -c cacert.pem"


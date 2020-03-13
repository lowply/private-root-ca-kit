#!/bin/bash

[ -z "${FQDN}" ] && { echo "FQDN env var is empty"; exit 1; }

patch -u /etc/ssl/openssl.cnf < ./openssl.cnf.patch
sed -i "s/domain.example.com/${FQDN}/" /etc/ssl/openssl.cnf

bash

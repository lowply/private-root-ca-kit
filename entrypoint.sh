#!/bin/bash

[ -z "${FQDN}" ] && { echo "FQDN env var is empty"; exit 1; }

cp -a /etc/ssl/misc/CA.pl /usr/local/bin
patch /usr/local/bin/CA.pl < CA.patch

cp -a /home/conf.d /etc/ssl
sed -i "s/domain.example.com/${FQDN}/" /etc/ssl/conf.d/openssl-sign.cnf
sed -i "s/domain.example.com/${FQDN}/" /etc/ssl/conf.d/openssl-server-req.cnf

for cnf in $(find /etc/ssl -type f -name "openssl*.cnf")
do
    [ -z "${DEFAULT_COUNTRY}" ] || sed -i "s/= AU/= ${DEFAULT_COUNTRY}/" ${cnf}
    [ -z "${DEFAULT_PROVINCE}" ] || sed -i "s/= Some-State/= ${DEFAULT_PROVINCE}/" ${cnf}
    [ -z "${DEFAULT_ORG}" ] || sed -i "s/= Internet Widgits Pty Ltd/= ${DEFAULT_ORG}/" ${cnf}
done

bash

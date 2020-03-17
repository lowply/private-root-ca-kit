# Private Root CA Kit

A toolkit to build your own private root CA and create a self-signed certificate signed by the CA.

Creating a self-signed certificate signed by a private authority is tricky, but it's useful when you're running local dev server with SSL/TLS. This article will go through the process of generating, signing and installing a self-signed certificate using a private authority on macOS.

In this example, certificate chain will be:

```
[Root CA] --> [Intermediate CA] --> [Server Certificate]
```

And each certificate has:

```
Root CA:            Subject: C=JP, ST=Tokyo, O=Fixture, CN=Fixture Root CA
Intermediate CA:    Subject: C=JP, ST=Tokyo, O=Fixture, CN=Fixture Intermediate CA
Server Certificate: Subject: C=JP, ST=Tokyo, O=Fixture, CN=${FQDN}
```

Please replace `${FQDN}` to the hostname of your server.

## Step 0 - Prep

Install Docker, clone this repository, cd into it and run:

```bash
./script/build.sh

export DEFAULT_COUNTRY="JP"
export DEFAULT_PROVINCE="Tokyo"
export DEFAULT_ORG="Fixture"
export FQDN="your.example.com"
./script/run.sh
```

This will build and run a docker container that has:

- The `openssl` command and the patched CA.pl script
- Custom OpenSSL config files in the */etc/ssl/conf.d* directory

## Step 1 - Create a private authority

You're in the container. Let's get started by creating a new private authority:

```bash
OPENSSL_CONFIG="-config /etc/ssl/conf.d/openssl-rootca.cnf" CA.pl -newca
```

Since you have default values in the conf files, just keep hitting enter key except the common name:

```bash
Common Name (e.g. server FQDN or YOUR name) []:Fixture Root CA
```

Check the certificate:

```bash
openssl x509 -in /home/CA/cacert.pem -text
```

- `Not After` date is ten years after the current date
- Issuer and Subject should be identical
- `X509v3 Basic Constraints` should be `CA:TRUE`

## Step 2 - Create an intermediate CA

Next, create an intermediate CA certificate. Don't have to set `OPENSSL_CONFIG`.

```bash
cd intermediateCA
CA.pl -newreq
```

Again, you have default values in the conf files, so just keep hitting enter key except the common name:

```bash
Common Name (e.g. server FQDN or YOUR name) []:Fixture Intermediate CA
```

Check the request

```bash
openssl req -in ./newreq.pem -text
```

Sign the intermediate certificate request by the root CA

```bash
OPENSSL_CONFIG="-config /etc/ssl/conf.d/openssl-signca.cnf" CA.pl -signCA
```

Check the certificate

```bash
openssl x509 -in ./newcert.pem -text
```

- `Not After` date is ten years after the current date

Reorganize the intermediate CA directory so that it can sign a server certificate in the next step.

```bash
mkdir private
mv newkey.pem private/cakey.pem
mv newcert.pem cacert.pem
mkdir newcerts
touch index.txt
echo 00 > serial
```

## Step 3 - Create a server certificte

Move back to the workdir and create a directory for the FQDN

```bash
mkdir /home/domains/${FQDN} && cd /home/domains/${FQDN}
```

Create a server certificate request.

```bash
OPENSSL_CONFIG="-config /etc/ssl/conf.d/openssl-server-req.cnf" CA.pl -newreq
```

Again, you have default values in the conf files, so just keep hitting enter key except the common name:

```bash
Common Name (e.g. server FQDN or YOUR name) []:${FQDN}
```

Check the request

```bash
openssl req -in ./newreq.pem -text
```

Check the `X509v3 Subject Alternative Name` field:

- Make sure you have the wildcard (`*.${FQDN}`) in the `X509v3 Subject Alternative Name` field.
- If you are using Google Chrome, make sure you have the FQDN (`${FQDN}`) in the `X509v3 Subject Alternative Name` field
  - Otherwise you'll see the `ERR_CERT_COMMON_NAME_INVALID` error
  - More info: [Support for commonName matching in Certificates (removed)](https://www.chromestatus.com/feature/4981025180483584)

## Step 4 - Sign the server certificate request by the intermediate CA

Sign the server certificate request by the intermediate CA

```bash
OPENSSL_CONFIG="-config /etc/ssl/conf.d/openssl-sign.cnf" CA.pl -sign
```

Check the certificate

```bash
openssl x509 -in ./newcert.pem -text
```

This Issuer should be the intermediate CA and it should have `X509v3 Subject Alternative Name` field.

## Step 5 - Prepare server certificate and private key

Create a certificate chain:

```bash
openssl x509 -in newcert.pem > cert.pem
openssl x509 -in ../../intermediateCA/cacert.pem >> cert.pem
```

Remove passphrase from private key and rename it:

```bash
openssl rsa -in newkey.pem -out key.pem
```

Ref: [Removing the passphrase from your key file](https://help.github.com/en/enterprise/2.20/admin/installation/troubleshooting-ssl-errors#removing-the-passphrase-from-your-key-file)

Verify the certificate and private key:

```bash
[ "$(openssl rsa -pubout -in key.pem 2> /dev/null)" = "$(openssl x509 -pubkey -in cert.pem -noout)" ] && echo "OK" || echo "Verification Failed"
```

Done, now let's exit from the container.

```bash
exit
```

## Step 6 - Install the root certificate to your Keychain (if you haven't done yet)

Next, let's install the root certificate to your macOS's Keychain app.

1. Add the certificate to Keychain by double clicking `CA/cacert.pem` file
2. Add it to the "System" keychain
3. In the Keychain, select the certificate
4. Right click -> Get Info
5. Change to "Always Trust"

Note that Firefox doesn't use Keychain so you have to add the root certificate manually if you're using Firefox.

### GitHub Enterprise Server

If you're using GitHub Enterprise Server, run the following:

```bash
./script/add-root.sh [hostname]
```

## Step 7 - Install the server certificate

Use the `domains/${FQDN}/cert.pem` and `domains/${FQDN}/key.pem` files.

### GitHub Enterprise Server

Run the following:

```bash
./script/ghes-install.sh [hostname] password
```

## Step 7 - Confirm SSL connection

Lastly, confirm the SSL connection with the `openssl` command.

```bash
openssl s_client -connect ${FQDN}:443 -verify 0 -CAfile ./CA/cacert.pem
```

Done!

---

Ref:

- [2 tierプライベート認証局を作る | Netsphere Laboratories](https://www.nslabs.jp/pki-making-two-tier-ca.rhtml)
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

Install Docker, clone this repository, cd to it and run:

```
export FQDN="your.example.com"
./script/build.sh
./script/run.sh
```

This will create a docker container that has

- The `openssl` command and the CA.pl script
- The *openssl.cnf* file with a patch applied with SANs of your FQDN

and run it.

## Step 1 - Create a private authority

You're in the container. Let's get started by creating a new private authority:

```
CA.pl -newca
```

- Enter to proceed
- `PEM pass phrase = [passphrase]`, 
- `Country Name = JP`
- `State or Province Name = Tokyo`
- `Locality Name = [empty]`
- `Organization Name = Fixture Root CA`
- `Organizational Unit Name = [empty]`
- `Common Name = Fixture Root CA`
- `Email Address = [empty]`
- `A challenge password = [empty]`
- `An optional company name = [empty]`

Check the certificate:

```
openssl x509 -in ./demoCA/cacert.pem -text
```

- Issuer and Subject should be identical
- `X509v3 Basic Constraints` should be `CA:TRUE`

## Step 2 - Create an intermediate CA

Next, create an intermediate CA certificate.

```
cd intermediateCA
CA.pl -newreq
```

- `PEM pass phrase = [password]`
- `Country Name = JP`
- `State or Province Name = Tokyo`, 
- `Locality Name = [empty]`, 
- `Organization Name = Fixture Intermediate CA`
- `Organizational Unit Name = [empty]`
- `Common Name = Fixture Intermediate CA`
- `Email Address = [empty]`
- `A challenge password = [empty]`

Check the request

```
openssl req -in ./newreq.pem -text
```

Sign the intermediate certificate request by the root CA

```
CA.pl -signCA
```

If it fails, truncate the *index.txt* file of the root CA and try again.

```
truncate -s0 ../../demoCA/index.txt
```

Check the certificate

```
openssl x509 -in ./newcert.pem -text
```

Make sure that the `Signature Algorithm` is `sha256WithRSAEncryption`.

Reorganize the intermediate CA directory so that it can sign a server certificate in the next step.

```
mkdir private
mv newkey.pem private/cakey.pem
mv newcert.pem cacert.pem
mkdir newcerts
touch index.txt
echo 00 > serial
```

## Step 3 - Create a server certificte

Move back to the workdir and create a directory for the FQDN

```
cd ..
mkdir domains/${FQDN}
cd domains/${FQDN}
```

Create a server certificate request.

```
CA.pl -newreq
```

- `PEM pass phrase = [password]`
- `Country Name = JP`
- `State or Province Name = Tokyo`, 
- `Locality Name = [empty]`, 
- `Organization Name = Fixture`
- `Organizational Unit Name = [empty]`
- `Common Name = ghe.fixture.jp`
- `Email Address = [empty]`
- `A challenge password = [empty]`

Check the request

```
openssl req -in ./newreq.pem -text
```

Check the `X509v3 Subject Alternative Name` field:

- Make sure you have the wildcard (`*.${FQDN}`) in the `X509v3 Subject Alternative Name` field.
- If you are using Google Chrome, make sure you have the FQDN (`${FQDN}`) in the `X509v3 Subject Alternative Name` field
  - Otherwise you'll see the `ERR_CERT_COMMON_NAME_INVALID` error
  - More info: [Support for commonName matching in Certificates (removed)](https://www.chromestatus.com/feature/4981025180483584)

## Step 4 - Sign the server certificate request by the intermediate CA

Sign the server certificate request by the intermediate CA

```
CA.pl -sign
```

If it fails, truncate the *index.txt* file of the intermediate CA and try again.

```
truncate -s0 ../../intermediateCA/index.txt
```

Check the certificate

```
openssl x509 -in ./newcert.pem -text
```

This Issuer should be the intermediate CA and it should have `X509v3 Subject Alternative Name` field.

## Step 5 - Prepare server certificate and private key

Create a certificate chain:

```
openssl x509 -in newcert.pem > cert.pem
openssl x509 -in ../../intermediateCA/cacert.pem >> cert.pem
```

Remove passphrase from private key and rename it:

```
openssl rsa -in newkey.pem -out key.pem
```

Ref: [Removing the passphrase from your key file](https://help.github.com/en/enterprise/2.20/admin/installation/troubleshooting-ssl-errors#removing-the-passphrase-from-your-key-file)

Verify the certificate and private key:

```
[ "$(openssl rsa -pubout -in key.pem 2> /dev/null)" = "$(openssl x509 -pubkey -in cert.pem -noout)" ] && echo "OK" || echo "Verification Failed"
```

Done, now let's exit from the container.

```
exit
```

## Step 6 - Install the root certificate to your Keychain (if you haven't done yet)

Next, let's install the root certificate to your macOS's Keychain app.

1. Add the certificate to Keychain by double clicking `demoCA/cacert.pem` file
1. Add it to the "System" keychain
1. In the Keychain, select the certificate
1. Right click -> Get Info
1. Change to "Always Trust"

Note that Firefox doesn't use Keychain so you have to add the root certificate manually if you're using Firefox.

### GitHub Enterprise Server

If you're using GitHub Enterprise Server, run the following:

```
./script/add_root [hostname]
```

## Step 7 - Install the server certificate

Use the `domains/${FQDN}/cert.pem` and `domains/${FQDN}/key.pem` files.

### GitHub Enterprise Server

Run the following:

```
./script/ghes-install.sh example.com password
```

## Step 7 - Confirm SSL connection

Lastly, confirm the SSL connection with the `openssl` command.

```
openssl s_client -connect ${FQDN}:443 -verify 0 -CAfile ./demoCA/cacert.pem
```

Done!
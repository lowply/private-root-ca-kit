# Private Root CA Kit

A tool kit to build your private root CA on macOS.

Creating a self-signed certificate signed by a private authority is tricky, but it's useful when you're running local dev server with SSL/TLS. This article will go through the process of generating, signing and installing a self-signed certificate using a private authority on macOS.

In this example, certificate chain will be:

```
[Root CA] --> [Intermediate CA] --> [Server Certificate]
```

And each certificate has:

```
Root CA:            Subject: C=JP, ST=Tokyo, L=Shibuya, O=Fixture, CN=Fixture Root CA
Intermediate CA:    Subject: C=JP, ST=Tokyo, L=Shibuya, O=Fixture, CN=Fixture Intermediate CA
Server Certificate: Subject: C=JP, ST=Tokyo, L=Shibuya, O=Fixture, CN=example.localhost
```

Please replace `example.localhost` to the hostname of your GitHub Enterprise instance.

## Step 0 - Install and prep

macOS High Sierra switched to LibreSSL

```
$ /usr/bin/openssl version
LibreSSL 2.2.7
```

But we'd like to use OpenSSL. Let's install OpenSSL via Homebrew and alias to it:

```
$ brew install openssl
$ /usr/local/opt/openssl/bin/openssl version
OpenSSL 1.0.2l  25 May 2017
$ alias openssl="/usr/local/opt/openssl/bin/openssl"
```

Prepare *CA.sh* script

```
cp -a /usr/local/etc/openssl/misc/CA.sh .
/usr/local/bin/gsed -i 's|OPENSSL=openssl|OPENSSL="/usr/local/opt/openssl/bin/openssl"|' CA.sh
```

## Step 1 - Create a private authority

In this repository, create a new private authority.

```
$ ./CA.sh -newca
```

- Enter `PEM pass phrase`, `Country Name`, `State or Province Name`, `Locality Name` and `Common Name`
- `Organizational Unit Name` and `Email Address` can be empty

Check the certificate

```
$ openssl x509 -in ./demoCA/cacert.pem -text
```

- Issuer and Subject should be identical
- `X509v3 Basic Constraints` should be `CA:TRUE`

## Step 2 - Create an intermediate CA

Next, create an intermediate CA certificate.

```
$ cd intermediateCA
$ ../CA.sh -newreq
```

- Enter `PEM pass phrase`, `Country Name`, `State or Province Name`, `Locality Name` and `Common Name`
- `Organizational Unit Name` and `Email Address` can be empty

Check the request

```
$ openssl req -in ./newreq.pem -text
```

Copy the *openssl.cnf* file and apply *sign-intermediate-ca.cnf.patch*

```
$ cp -a /usr/local/etc/openssl/openssl.cnf ./sign-intermediate-ca.cnf
$ patch -u sign-intermediate-ca.cnf < ../patch/sign-intermediate-ca.cnf.patch
```

Sign the intermediate certificate request by the root CA

```
$ SSLEAY_CONFIG="-config sign-intermediate-ca.cnf" ../CA.sh -signCA
```

Check the certificate

```
$ openssl x509 -in ./newcert.pem -text
```

Reorganize the intermediate CA directory so that it can sign a server certificate in the next step.

```
$ mkdir private
$ mv newkey.pem private/cakey.pem
$ mv newcert.pem cacert.pem
$ mkdir newcerts
$ touch index.txt
$ echo 00 > serial
```

## Step 3 - Create a server certificte

Move back to the workdir and create a directory for the FQDN

```
$ cd ..
$ mkdir domains/example.localhost
$ cd domains/example.localhost
```

Generate the *server-req.cnf.patch* file by replacing the FQDNs in the `alt_names` section of the *server-req.cnf.patch.template* file.

```
$ cat ../../patch/server-req.cnf.patch.template | sed -e 's/example.com/example.localhost/g' > server-req.cnf.patch
```

Copy the *openssl.cnf* file and apply the patch

```
$ cp -a /usr/local/etc/openssl/openssl.cnf ./server-req.cnf
$ patch -u server-req.cnf < server-req.cnf.patch
```

Create a server certificate request

```
$ SSLEAY_CONFIG="-config server-req.cnf" ../../CA.sh -newreq
```

Check the request

```
$ openssl req -in ./newreq.pem -text
```

Check the `X509v3 Subject Alternative Name` field:

- Make sure you have the wildcard (`*.example.localhost`) in the `X509v3 Subject Alternative Name` field.
- If you are using Google Chrome, make sure you have the FQDN (`example.localhost`) in the `X509v3 Subject Alternative Name` field
  - Otherwise you'll see the `ERR_CERT_COMMON_NAME_INVALID` error
  - More info: [Support for commonName matching in Certificates (removed)](https://www.chromestatus.com/feature/4981025180483584)

## Step 4 - Sign the server certificate request by the intermediate CA

Generate the *sign-server-cert.cnf.patch* file by replacing the FQDNs in the `alt_names` section of the *sign-server-cert.cnf.patch.template* file.

```
$ cat ../../patch/sign-server-cert.cnf.patch.template | sed -e 's/example.com/example.localhost/g' > sign-server-cert.cnf.patch
```

Copy the *openssl.cnf* file and apply the patch

```
$ cp -a /usr/local/etc/openssl/openssl.cnf ./sign-server-cert.cnf
$ patch -u sign-server-cert.cnf < sign-server-cert.cnf.patch
```

Sign the server certificate request by the intermediate CA

```
$ SSLEAY_CONFIG="-config sign-server-cert.cnf" ../../CA.sh -sign
```

Check the certificate

```
$ openssl x509 -in ./newcert.pem -text
```

This Issuer should be the intermediate CA and it should have `X509v3 Subject Alternative Name` field.

## Step 5 - Install the root certificate to your Keychain (if you haven't done yet)

Next, let's install the root certificate to your macOS's Keychain app.

1. Add the certificate to Keychain by double clicking `demoCA/cacert.pem` file
1. Add it to the "System" keychain
1. In the Keychain, select the certificate
1. Right click -> Get Info
1. Change to "Always Trust"

Note that Firefox doesn't use Keychain so you have to add the root certificate manually if you're using Firefox.

## Step 6 - Install the server certificate to your dev server

Create a certificate chain:

```
$ mkdir $(date +%y%m%d)
$ openssl x509 -in newcert.pem > $(date +%y%m%d)/cert.pem
$ openssl x509 -in ../../intermediateCA/cacert.pem >> $(date +%y%m%d)/cert.pem
```

Remove passphrase from private key and rename it:

```
$ openssl rsa -in newkey.pem -out $(date +%y%m%d)/key.pem
```

Verify the certificate and private key:

```
$ [ "$(openssl rsa -pubout -in $(date +%y%m%d)/key.pem 2> /dev/null)" = "$(openssl x509 -pubkey -in $(date +%y%m%d)/cert.pem -noout)" ] && echo "OK" || echo "Verification Failed"
OK
```

Install the cert and key.

## Step 7 - Confirm SSL connection

Lastly, confirm the SSL connection with the `openssl` command.

```
$ openssl s_client -connect example.localhost:443 -verify 0 -CAfile ../../demoCA/cacert.pem
verify depth is 0
CONNECTED(00000003)
depth=2 /C=JP/ST=Tokyo/O=Fixture/CN=Fixture Root CA
verify return:1
depth=1 /C=JP/ST=Tokyo/L=Shibuya/O=Fixture/CN=Fixture Intermediate CA
verify return:1
depth=0 /C=JP/ST=Tokyo/L=Shibuya/O=Fixture/CN=example.localhost
verify return:1
---
Certificate chain
 0 s:/C=JP/ST=Tokyo/L=Shibuya/O=Fixture/CN=example.localhost
   i:/C=JP/ST=Tokyo/L=Shibuya/O=Fixture/CN=Fixture Intermediate CA
 1 s:/C=JP/ST=Tokyo/L=Shibuya/O=Fixture/CN=Fixture Intermediate CA
   i:/C=JP/ST=Tokyo/O=Fixture/CN=Fixture Root CA
---
Server certificate
-----BEGIN CERTIFICATE-----
MIIERDCCAyygAwIBAgIBADANBgkqhkiG9w0BAQsFADBjMQswCQYDVQQGEwJKUDEO
MAwGA1UECAwFVG9reW8xEDAOBgNVBAcMB1NoaWJ1eWExEDAOBgNVBAoMB0ZpeHR1
cmUxIDAeBgNVBAMMF0ZpeHR1cmUgSW50ZXJtZWRpYXRlIENBMB4XDTE3MDcyNTE3
NDIxMFoXDTE4MDcyNTE3NDIxMFowcDELMAkGA1UEBhMCSlAxDjAMBgNVBAgMBVRv
a3lvMRAwDgYDVQQHDAdTaGlidXlhMSEwHwYDVQQKDBhJbnRlcm5ldCBXaWRnaXRz
IFB0eSBMdGQxHDAaBgNVBAMME2xvd3BseS5naGUtdGVzdC5uZXQwggEiMA0GCSqG
SIb3DQEBAQUAA4IBDwAwggEKAoIBAQDQQh1WZqbpsPdmOOgPGKIGTYpPakTPNYIO
l8+HvcZR21iGToHfZMmcgLriqT49OFLG7z6uToedbaLP9vktSerjYWVs/GEg1WOo
GA73VpOeR7+w2+p/1q3u4IgCPY+4GLobOX21dr4LmEiifF8B32PB2+hmeUUrYHRs
+j5hwkpE/q9fujv8ZKFHvLCSrjdSq/nT+t9lbo+mcQVp8crdZhflI5Koh5Xc0qY4
HSFALcBU6wQTRK4IhyC1Y0qxAYnskjLkNds1kKoYyqxGJmRV0gA7QJmQ60M/Z988
IIQwws+S8qtCJMorcAydcB7qShxI3hH67OdQZPkMpMaY/7pZQW2TAgMBAAGjgfUw
gfIwDAYDVR0TAQH/BAIwADARBglghkgBhvhCAQEEBAMCBkAwCwYDVR0PBAQDAgXg
MB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjA1BgNVHREELjAsghUqLmxv
d3BseS5naGUtdGVzdC5uZXSCE2xvd3BseS5naGUtdGVzdC5uZXQwLAYJYIZIAYb4
QgENBB8WHU9wZW5TU0wgR2VuZXJhdGVkIENlcnRpZmljYXRlMB0GA1UdDgQWBBTD
GtgIhi+UVVPvBdn3KVUjo3s98TAfBgNVHSMEGDAWgBTr0L6eyBvhkF4WLG19m7zp
BJfgVDANBgkqhkiG9w0BAQsFAAOCAQEAT4zzu5BtA8nHCaVdhSeosBP6WGc24IMz
sJh3AMjqyTOOq0Le3tuzuvyLAmlKTOv0W3Hwt53ezALDZkZ+7lWSpz6Lx0dD8+xA
iS+GxCdKdOXJLBuxkKzfMtct5dbm9e5wL1pstEL7UOpGugjYQdkgoR92mbqfGcPc
AXVJkHeHllYMbxs/CvKLQmhS/FH280Apbl2SKmEGca6VAa0xRJbktLvkBDvkgmFO
1AB2Skj46fQxJXzsWQYKf4SYOXBlkWKIlP+bvc9hqh9DGoyJxbRyUtruLtTCY3Ej
ZxA7FnSInoyH+8ezG7/Cz9X+DOtI6G7RNpqqksWsYnnmww8qNvZZQQ==
-----END CERTIFICATE-----
subject=/C=JP/ST=Tokyo/L=Shibuya/O=Fixture/CN=example.localhost
issuer=/C=JP/ST=Tokyo/L=Shibuya/O=Fixture/CN=Fixture Intermediate CA
---
No client certificate CA names sent
---
SSL handshake has read 2202 bytes and written 456 bytes
---
New, TLSv1/SSLv3, Cipher is AES128-SHA
Server public key is 2048 bit
Secure Renegotiation IS supported
Compression: NONE
Expansion: NONE
SSL-Session:
    Protocol  : TLSv1
    Cipher    : AES128-SHA
    Session-ID: ECA6E3705FE81BDA70741E6149DC51C043286BC0DC8E3EEA8D9D864C531D6B43
    Session-ID-ctx:
    Master-Key: 9B43DDA76EDDF479AF94BA3908F5F1117F93083D835F9D699F6EC64359995F35D9952333B3FCD417C129A69D35C3A042
    Key-Arg   : None
    Start Time: 1501121486
    Timeout   : 300 (sec)
    Verify return code: 0 (ok)
---
```

Done!

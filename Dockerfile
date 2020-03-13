FROM alpine:latest

WORKDIR /home
RUN apk add bash perl openssl
RUN ln -s /etc/ssl/misc/CA.pl /usr/local/bin
COPY ./openssl.cnf.patch .
COPY ./entrypoint.sh .

ENTRYPOINT ["./entrypoint.sh"]

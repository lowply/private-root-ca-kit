FROM alpine:latest

WORKDIR /home
RUN apk add bash perl openssl
COPY ./entrypoint.sh .

ENTRYPOINT ["./entrypoint.sh"]

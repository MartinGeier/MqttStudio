#!/bin/sh
# Generates the certificates of test/mqtt/tls_context_test.dart: a CA, a server certificate for localhost and a
# client certificate, all valid for 100 years. Run it from this directory, in Git Bash with MSYS_NO_PATHCONV=1.
set -e
openssl req -x509 -newkey rsa:2048 -nodes -days 36500 -subj "/CN=MQTT Studio Test CA" -keyout ca.key -out ca.crt
openssl req -newkey rsa:2048 -nodes -subj "/CN=localhost" -keyout server.key -out server.csr
printf "subjectAltName=DNS:localhost,IP:127.0.0.1\n" > server.ext
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 36500 -extfile server.ext -out server.crt
openssl req -newkey rsa:2048 -nodes -subj "/CN=mqttstudio-test-client" -keyout client.key -out client.csr
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 36500 -out client.crt
openssl pkcs8 -topk8 -v2 aes-256-cbc -in client.key -passout pass:secret -out client-encrypted.key
cat client.crt client.key > client-combined.pem
rm -f server.csr client.csr server.ext ca.srl ca.key

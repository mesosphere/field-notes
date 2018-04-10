# Local Universe

Contents unformatted.  TODO later.

This is a HUGE work in progress, but is meant to outline using the DC/OS CA to sign the certificates on the local universe (rather than using self-signed certs)

**Cannot be done on OSX. Must be done on Linux**

prereqs

TODO: install Docker

```bash
sudo yum install -y git make epel-release openssl; 
sudo yum install -y python34-pip; 
sudo sudo pip3 install jsonschema
```

Get repo
```bash
git clone https://github.com/mesosphere/universe.git
cd universe
```

Generate CA-signed certs:
```bash
####### make working directory
mkdir -p docker/local-universe/static-certs
cd docker/local-universe/static-certs

###### Setup env (REPLACE WITH RELEVANT ITEMS)
# Auth
export USERNAME=bootstrapuser
export PASSWORD=deleteme
export MASTER_IP=10.10.0.58
# Hostname of location where cluster will be hosted (TODO: support hosting somewhere else)
export CANONICAL_NAME="master.mesos"
## Replace with the hostname, fqdn, and ip address of server you're generating the certificate for.
export LIST_OF_HOSTS='"master.mesos", "10.10.0.58", "10.10.0.150", "10.10.0.245", "54.201.45.78", "54.149.239.153", "34.217.26.216"' 

###### Authenticate
echo '{"uid": "USERNAME", "password": "PASSWORD"}' > login_request.json
sed -i "s/USERNAME/${USERNAME}/" login_request.json
sed -i "s/PASSWORD/${PASSWORD}/" login_request.json

## POST the JSON file to the auth login API
curl -k https://${MASTER_IP}/acs/api/v1/auth/login \
    -X POST \
    -H 'content-type:application/json' \
    -d @login_request.json \
    > login_token.json

## Parse the JSON response and save the token to a text file
cat login_token.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["token"]' > token
rm login_request.json
rm login_token.json

## Verify that you have an authorization token
cat token

###### Make CSR request (i.e., request FOR csr) to get CSR
echo '{
    "CN": "CANONICAL_NAME",
    "key": {"algo": "rsa", "size": 4096},
    "hosts": [LIST_OF_HOSTS]
}' > key_request.json

sed -i "s/CANONICAL_NAME/${CANONICAL_NAME}/" key_request.json
sed -i "s/LIST_OF_HOSTS/${LIST_OF_HOSTS}/" key_request.json

## Verify the JSON looks correct
cat key_request.json

## POST it
curl -k https://${MASTER_IP}/ca/api/v2/newkey \
    -X POST \
    -H 'content-type:application/json'  \
    -d @key_request.json \
    -H "Authorization: token=$(cat token)" \
    > newkey.json

###### Reformat

## Extract the key from JSON to a single-line PEM
cat newkey.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["result"]["private_key"]' > key.pem.oneline

## Convert the single-line PEM to a PEM file (may or may not be necessary)
cat key.pem.oneline | sed 's:\\n:\n:g' > ${CANONICAL_NAME}.key

## Extract the CSR into a new JSON
cat newkey.json | python -c 'import sys,json;j=sys.stdin.read();f=json.loads(j);csr={"certificate_request":f["result"]["certificate_request"]};print(json.dumps(csr))' > ${CANONICAL_NAME}.csr.json

## Clean up
rm key_request.json
rm newkey.json
rm key.pem.oneline

###### Submit CSR and get certificate
curl -k https://${MASTER_IP}/ca/api/v2/sign \
    -X POST \
    -H 'content-type:application/json'  \
    -d @${CANONICAL_NAME}.csr.json \
    -H "Authorization: token=$(cat token)" \
    > certificate.json

# Reformat json to PEM file (.crt)
cat certificate.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["result"]["certificate"]' > ${CANONICAL_NAME}.crt

# Clean up
rm certificate.json
rm ${CANONICAL_NAME}.csr.json

###### Clean up token
rm token

###### Copy to domain.* files
cp ${CANONICAL_NAME}.crt domain.crt
cp ${CANONICAL_NAME}.key domain.key

###### Go back to local-universe directory
cd ..
```

Modify Dockerfile to use static certs
```bash
sed -i 's/certs/static-certs/' Dockerfile.base | grep static
```

Modify Dockerfile to use better keyserver
```bash
sed -i 's|hkp://pgp.mit.edu:80|zimmermann.mayfirst.org|' Dockerfile.base
```

Make the local universe
```bash
make DCOS_VERSION=1.11 DCOS_PACKAGE_INCLUDE="kubernetes:1.0.2-1.9.6" local-universe
```
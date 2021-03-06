# This document details how to make API queries that are usually wrapped by the `dcos security` subcommand package, without the subcommand package.

```bash

##############################################################################################
#### Get token (and write it to file 'token')
export MASTER_IP=10.10.0.65
export USERNAME=admin
export PASSWORD=password
echo '{"uid": "USERNAME", "password": "PASSWORD"}' > login_request.json
sed -i "s/USERNAME/${USERNAME}/" login_request.json
sed -i "s/PASSWORD/${PASSWORD}/" login_request.json

curl -sk https://${MASTER_IP}/acs/api/v1/auth/login \
    -X POST \
    -H 'content-type:application/json' \
    -d @login_request.json \
    > login_token.json

cat login_token.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["token"]' > token
rm login_request.json
rm login_token.json

export TOKEN=$(cat token)

##############################################################################################
##### Create RSA public/private key pair
##### dcos security org service-accounts keypair ${PRINCIPAL}-private.pem ${PRINCIPAL}-public.pem
export PRINCIPAL="marathon-lb"

export PRIVATE_KEY_FILE="${PRINCIPAL}-private.pem"
export PUBLIC_KEY_FILE="${PRINCIPAL}-public.pem"
# openssl genrsa -out ${PRIVATE_KEY_FILE} 2048
openssl genpkey -out ${PRIVATE_KEY_FILE} -algorithm RSA -pkeyopt rsa_keygen_bits:2048
openssl rsa -in ${PRIVATE_KEY_FILE} -pubout -out ${PUBLIC_KEY_FILE}

##############################################################################################
##### Create service account (with public key)
##### dcos security org service-accounts create -p ${PRINCIPAL}-public.pem ${PRINCIPAL}

## These are already set from above
# export PRINCIPAL="marathon-lb"
# export PUBLIC_KEY_FILE="${PRINCIPAL}-public.pem"
# export TOKEN=$(cat token)
# export MASTER_IP=10.10.0.65

## These are new
export SERVICE_ACCOUNT=${PRINCIPAL}

tee ${SERVICE_ACCOUNT}-service-account.json <<-'EOF'
{
  "description": "service account `SERVICE_ACCOUNT`",
  "public_key": "PUBLIC_KEY"
}
EOF

# The public key must have escaped endlines
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${SERVICE_ACCOUNT}-service-account.json
sed -i "s|PUBLIC_KEY|$(sed 's|$|\\\\n|g' ${PUBLIC_KEY_FILE} | tr -d '\n')|g" ${SERVICE_ACCOUNT}-service-account.json

# Create service account
curl -sk https://${MASTER_IP}/acs/api/v1/users/${SERVICE_ACCOUNT} \
    -X PUT \
    -H "authorization: token=${TOKEN}" \
    -H 'content-type:application/json' \
    -d @${SERVICE_ACCOUNT}-service-account.json

##############################################################################################
##### Create service account secret (with private key)
##### dcos security secrets create-sa-secret --strict ${PRINCIPAL}-private.pem ${PRINCIPAL} ${SERVICE_ACCOUNT_SECRET}

## These are already set from above
# export PRINCIPAL="marathon-lb"
# export PRIVATE_KEY_FILE=${PRINCIPAL}-private.pem
# export TOKEN=$(cat token)
# export MASTER_IP=10.10.0.65
# export SERVICE_ACCOUNT=${PRINCIPAL}

## These are new
export SERVICE_NAME="marathon-lb"
export SERVICE_ACCOUNT_SECRET="${SERVICE_NAME}/sa"

tee ${PRINCIPAL}-secret.json <<-'EOF'
{
"login_endpoint":"https://leader.mesos/acs/api/v1/auth/login",
"private_key":"PRIVATE_KEY",
"scheme":"RS256",
"uid":"SERVICE_ACCOUNT"
}
EOF

# This is the contents ('value') of the secret, which is JSON-formatted
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${PRINCIPAL}-secret.json
sed -i "s|PRIVATE_KEY|$(sed 's|$|\\\\n|g' ${PRIVATE_KEY_FILE} | tr -d '\n')|g" ${PRINCIPAL}-secret.json

# This is the full secret, which is JSON formatted, and has the escaped JSON-formatted secret as a value
echo -n '{"value": "' > ${PRINCIPAL}-secret.json.json
sed 's|\\|\\\\|g' ${PRINCIPAL}-secret.json | sed 's|"|\\"|g' | tr -d '\n' >> ${PRINCIPAL}-secret.json.json
echo '"}' >> ${PRINCIPAL}-secret.json.json

# Create the secret
curl -sk https://${MASTER_IP}/secrets/v1/secret/default/${SERVICE_ACCOUNT_SECRET} \
    -X PUT \
    -H "authorization: token=${TOKEN}" \
    -H 'content-type:application/json' \
    -d @${PRINCIPAL}-secret.json.json

##############################################################################################
##### Grant permission to user
##### dcos security org users grant ${PRINCIPAL} $p

## These are already set from above
# export PRINCIPAL="marathon-lb"
# export SERVICE_ACCOUNT=${PRINCIPAL}
# export TOKEN=$(cat token)
# export MASTER_IP=10.10.0.65

## These are new
export PERMISSION_ID="dcos:service:marathon:marathon:services:/"
export PERMISSION_ACTION="read"


export ESCAPED_PERMISSION_ID=$(echo ${PERMISSION_ID} | sed 's|/|%252F|g')

export FLAT_PERMISSION_ID=$(echo ${PERMISSION_ID} | sed 's|:|.|g' | sed 's|/|__|g')

tee ${FLAT_PERMISSION_ID}.json <<-'EOF'
{
  "description": "PERMISSION_ID"
}
EOF

sed -i "s|PERMISSION_ID|${PERMISSION_ID}|g" ${FLAT_PERMISSION_ID}.json

# Create the permission id
# It is okay if this responds with a 409
curl -sk https://${MASTER_IP}/acs/api/v1/acls/${ESCAPED_PERMISSION_ID} \
    -X PUT \
    -H "authorization: token=${TOKEN}" \
    -H 'content-type:application/json' \
    -d @${FLAT_PERMISSION_ID}.json

# Grant the permission/action to the user
curl -sk https://${MASTER_IP}/acs/api/v1/acls/${ESCAPED_PERMISSION_ID}/users/${SERVICE_ACCOUNT}/${PERMISSION_ACTION} \
    -X PUT \
    -H "authorization: token=${TOKEN}" \
    -H 'content-type:application/json' \
    -d @${FLAT_PERMISSION_ID}.json
```
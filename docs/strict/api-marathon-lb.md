This is a parameterized way to install Marathon-LB in strict mode, without the `dcos security` command line tool

# Create key and service account
```bash
#!/bin/bash


##############################################################################################
###### Customize environment here 
## Do not specify a leading slash ('/')
export SERVICE_NAME="marathon-lb"
## Example alternative
# export SERVICE_NAME="prod-app/stage/marathon-lb"
export PACKAGE_NAME="marathon-lb"
export PACKAGE_VERSION="1.12.2"

export MARATHON_LOCATION="/"
export HAPROXY_GROUP="external"

# Auth stuff
export MASTER_IP=10.10.0.65
export USERNAME=admin
export PASSWORD=password

##############################################################################################
#### Get token (and write it to file 'token')
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

# principal is SERVICE_NAME with slashes replaced with '__'
export PRINCIPAL=$(echo ${SERVICE_NAME} | sed "s|/|__|g")

# Service account secret is only accessible to the service
export SERVICE_ACCOUNT=${PRINCIPAL}
export SERVICE_ACCOUNT_SECRET="${SERVICE_NAME}/sa"

# Used for filenames
export PACKAGE_OPTIONS_FILE="${PRINCIPAL}-options.json"
export PERMISSION_LIST_FILE="${PRINCIPAL}-permissions.txt"

export PRIVATE_KEY_FILE="${PRINCIPAL}-private.pem"
export PUBLIC_KEY_FILE="${PRINCIPAL}-public.pem"

##############################################################################################
## Create service account private / public key pair
# dcos security org service-accounts keypair ${PRINCIPAL}-private.pem ${PRINCIPAL}-public.pem
# openssl genrsa -out ${PRIVATE_KEY_FILE} 2048
openssl genpkey -out ${PRIVATE_KEY_FILE} -algorithm RSA -pkeyopt rsa_keygen_bits:2048
openssl rsa -in ${PRIVATE_KEY_FILE} -pubout -out ${PUBLIC_KEY_FILE}

##############################################################################################
## Create service account
# dcos security org service-accounts create -p ${PRINCIPAL}-public.pem ${PRINCIPAL}

tee ${PRINCIPAL}-service-account.json <<-'EOF'
{
  "description": "service account `SERVICE_ACCOUNT`",
  "public_key": "PUBLIC_KEY"
}
EOF

# The public key must have escaped endlines
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${PRINCIPAL}-service-account.json
sed -i "s|PUBLIC_KEY|$(sed 's|$|\\\\n|g' ${PUBLIC_KEY_FILE} | tr -d '\n')|g" ${PRINCIPAL}-service-account.json

# Create the account with a PUT
curl -sk https://${MASTER_IP}/acs/api/v1/users/${SERVICE_ACCOUNT} \
    -X PUT \
    -H "authorization: token=${TOKEN}" \
    -H 'content-type:application/json' \
    -d @${PRINCIPAL}-service-account.json

##############################################################################################
## Create service account secret
# dcos security secrets create-sa-secret --strict ${PRINCIPAL}-private.pem ${PRINCIPAL} ${SERVICE_ACCOUNT_SECRET}

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
## Create permissions file and grant secrets
tee ${PERMISSION_LIST_FILE} <<-'EOF'
dcos:service:marathon:marathon:services:MARATHON_LOCATION read
dcos:service:marathon:marathon:admin:events read
EOF

sed -i "s|MARATHON_LOCATION|${MARATHON_LOCATION}|g" ${PERMISSION_LIST_FILE}

## Add permissions
while read p; do
  export PERMISSION_ARRAY=(${p})
  export PERMISSION_ID=${PERMISSION_ARRAY[0]}
  export PERMISSION_ACTION=${PERMISSION_ARRAY[1]}
  export ESCAPED_PERMISSION_ID=$(echo ${PERMISSION_ID} | sed 's|/|%252F|g')
  export FLAT_PERMISSION_ID=$(echo ${PERMISSION_ID} | sed 's|:|.|g' | sed 's|/|__|g')

  echo '{"description": "PERMISSION_ID"}' > ${FLAT_PERMISSION_ID}.json
  
  sed -i "s|PERMISSION_ID|${PERMISSION_ID}|g" ${FLAT_PERMISSION_ID}.json

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
      
done < ${PERMISSION_LIST_FILE}

##############################################################################################
## Create options file and install package
tee ${PACKAGE_OPTIONS_FILE} <<-'EOF'
{
  "marathon-lb": {
    "name": "SERVICE_NAME",
    "secret_name":"SERVICE_ACCOUNT_SECRET",
    "haproxy-group": "HAPROXY_GROUP",
    "marathon-uri": "https://marathon.mesos:8443"
  }
}
EOF

sed -i "s|SERVICE_ACCOUNT_SECRET|${SERVICE_ACCOUNT_SECRET}|g" ${PACKAGE_OPTIONS_FILE}
sed -i "s|HAPROXY_GROUP|${HAPROXY_GROUP}|g" ${PACKAGE_OPTIONS_FILE}
sed -i "s|SERVICE_NAME|${SERVICE_NAME}|g" ${PACKAGE_OPTIONS_FILE}

## Install
dcos package install ${PACKAGE_NAME} --package-version=${PACKAGE_VERSION} --options=${PACKAGE_OPTIONS_FILE} --yes --app
```
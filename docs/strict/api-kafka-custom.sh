#!/bin/bash

##############################################################################################
###### Customize environment here 
# Do not specify a leading slash ('/')
export SERVICE_NAME="kafka"
# export SERVICE_NAME="dev-stage/path/kafka-with-custom-zookeeper"

export PACKAGE_NAME="kafka"
export PACKAGE_VERSION="2.3.0-1.1.0"

# Either directly specify ZK_URI, or specify the service_name for kafka-zookeeper
export ZK_SERVICE_NAME="kafka-zookeeper"
# export ZK_SERVICE_NAME="dev-stage/path/kafka-zookeeper"
export ZK_SERVICE_DNS_NAME=$(echo ${ZK_SERVICE_NAME} | sed "s|/||g")
export ZK_URI="zookeeper-0-server.${ZK_SERVICE_DNS_NAME}.autoip.dcos.thisdcos.directory:1140,zookeeper-1-server.${ZK_SERVICE_DNS_NAME}.autoip.dcos.thisdcos.directory:1140,zookeeper-2-server.${ZK_SERVICE_DNS_NAME}.autoip.dcos.thisdcos.directory:1140"

## Cluster info
export MASTER_IP="10.10.0.228"

## If using username/password
export USERNAME="admin"
export PASSWORD="thisismypassword"
## If using token
# export TOKEN=""

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
rm token

##############################################################################################
###### Env variables based on customizations

# You can call the principal anything, but it makes the permissions harder; the principal must match the service account name for reservation deletion.
# principal is SERVICE_NAME with slashes replaced with '__'
export SERVICE_ACCOUNT=$(echo ${SERVICE_NAME} | sed "s|/|__|g")

# dns is generated from SERVICE_NAME with slashes removed
export SERVICE_DNS_NAME="$(echo ${SERVICE_NAME} | sed 's|/||g')"

# Service account secret is only accessible to the service
export SERVICE_ACCOUNT_SECRET="${SERVICE_NAME}/sa"

export SERVICE_ROLE="${SERVICE_ACCOUNT}-role"

# Used for filenames
export PACKAGE_OPTIONS_FILE="${SERVICE_ACCOUNT}-options.json"
export PERMISSION_LIST_FILE="${SERVICE_ACCOUNT}-permissions.txt"
export ENDPOINT_FILE="${SERVICE_ACCOUNT}-endpoints.txt"
export PRIVATE_KEY_FILE="${SERVICE_ACCOUNT}-private.pem"
export PUBLIC_KEY_FILE="${SERVICE_ACCOUNT}-public.pem"
export SERVICE_ACCOUNT_JSON="${SERVICE_ACCOUNT}-service-account.json"
export SERVICE_ACCOUNT_SECRET_JSON="${SERVICE_ACCOUNT}-secret.json"
export SERVICE_ACCOUNT_SECRET_FULL_JSON="${SERVICE_ACCOUNT}-secret.json.json"

##############################################################################################
## Create service account private / public key pair
# dcos security org service-accounts keypair ${SERVICE_ACCOUNT}-private.pem ${SERVICE_ACCOUNT}-public.pem
# openssl genrsa -out ${PRIVATE_KEY_FILE} 2048
openssl genpkey -out ${PRIVATE_KEY_FILE} -algorithm RSA -pkeyopt rsa_keygen_bits:2048
openssl rsa -in ${PRIVATE_KEY_FILE} -pubout -out ${PUBLIC_KEY_FILE}

##############################################################################################
## Create service account
# dcos security org service-accounts create -p ${SERVICE_ACCOUNT}-public.pem ${SERVICE_ACCOUNT}

tee ${SERVICE_ACCOUNT_JSON} <<-'EOF'
{
  "description": "service account `SERVICE_ACCOUNT`",
  "public_key": "PUBLIC_KEY"
}
EOF

# The public key must have escaped endlines
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${SERVICE_ACCOUNT_JSON}
sed -i "s|PUBLIC_KEY|$(sed 's|$|\\\\n|g' ${PUBLIC_KEY_FILE} | tr -d '\n')|g" ${SERVICE_ACCOUNT_JSON}

# Create the account with a PUT
curl -sk https://${MASTER_IP}/acs/api/v1/users/${SERVICE_ACCOUNT} \
    -X PUT \
    -H "authorization: token=${TOKEN}" \
    -H 'content-type:application/json' \
    -d @${SERVICE_ACCOUNT_JSON}

##############################################################################################
## Create service account secret
# dcos security secrets create-sa-secret --strict ${SERVICE_ACCOUNT}-private.pem ${SERVICE_ACCOUNT} ${SERVICE_ACCOUNT_SECRET}

tee ${SERVICE_ACCOUNT_SECRET_JSON} <<-'EOF'
{
"login_endpoint":"https://leader.mesos/acs/api/v1/auth/login",
"private_key":"PRIVATE_KEY",
"scheme":"RS256",
"uid":"SERVICE_ACCOUNT"
}
EOF

# This is the contents ('value') of the secret, which is JSON-formatted
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${SERVICE_ACCOUNT_SECRET_JSON}
sed -i "s|PRIVATE_KEY|$(sed 's|$|\\\\n|g' ${PRIVATE_KEY_FILE} | tr -d '\n')|g" ${SERVICE_ACCOUNT_SECRET_JSON}

# This is the full secret, which is JSON formatted, and has the escaped JSON-formatted secret as a value
echo -n '{"value": "' > ${SERVICE_ACCOUNT_SECRET_FULL_JSON}
sed 's|\\|\\\\|g' ${SERVICE_ACCOUNT_SECRET_JSON} | sed 's|"|\\"|g' | tr -d '\n' >> ${SERVICE_ACCOUNT_SECRET_FULL_JSON}
echo '"}' >> ${SERVICE_ACCOUNT_SECRET_FULL_JSON}

# Create the secret
curl -sk https://${MASTER_IP}/secrets/v1/secret/default/${SERVICE_ACCOUNT_SECRET} \
    -X PUT \
    -H "authorization: token=${TOKEN}" \
    -H 'content-type:application/json' \
    -d @${SERVICE_ACCOUNT_SECRET_FULL_JSON}

##############################################################################################
# Create list of permissions
# These may not all be necessary, but it does work.
# The 'role' permissions grant permission to create a reservation - need create only
# The 'principal' permissions grant permission to delete a reservation - need delete only
tee ${PERMISSION_LIST_FILE} <<-'EOF'
dcos:mesos:master:framework:role:SERVICE_ROLE       create
dcos:mesos:master:reservation:role:SERVICE_ROLE     create
dcos:mesos:master:volume:role:SERVICE_ROLE          create
dcos:mesos:master:task:user:nobody                  create
dcos:mesos:master:reservation:principal:SERVICE_ACCOUNT   delete
dcos:mesos:master:volume:principal:SERVICE_ACCOUNT        delete
EOF

sed -i "s|SERVICE_ROLE|${SERVICE_ROLE}|g" ${PERMISSION_LIST_FILE}
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${PERMISSION_LIST_FILE}

##############################################################################################
## Grant permissions
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

  rm ${FLAT_PERMISSION_ID}.json
      
done < ${PERMISSION_LIST_FILE}

##############################################################################################
## Create options file and install package

tee ${PACKAGE_OPTIONS_FILE} <<-'EOF'
{
  "service": {
    "name": "SERVICE_NAME",
    "service_account":"SERVICE_ACCOUNT",
    "service_account_secret": "SERVICE_ACCOUNT_SECRET"
  },
  "kafka": {
    "kafka_zookeeper_uri": "ZK_URI"
  }
}
EOF

sed -i "s|SERVICE_ACCOUNT_SECRET|${SERVICE_ACCOUNT_SECRET}|g" ${PACKAGE_OPTIONS_FILE}
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${PACKAGE_OPTIONS_FILE}
sed -i "s|SERVICE_NAME|${SERVICE_NAME}|g" ${PACKAGE_OPTIONS_FILE}
sed -i "s|ZK_URI|${ZK_URI}|g" ${PACKAGE_OPTIONS_FILE}

dcos package install ${PACKAGE_NAME} --package-version=${PACKAGE_VERSION} --options=${PACKAGE_OPTIONS_FILE} --yes --app

echo "zookeeper-0-server.${SERVICE_DNS_NAME}.autoip.dcos.thisdcos.directory:1140,zookeeper-1-server.${SERVICE_DNS_NAME}.autoip.dcos.thisdcos.directory:1140,zookeeper-2-server.${SERVICE_DNS_NAME}.autoip.dcos.thisdcos.directory:1140" > ${ENDPOINT_FILE}

##############################################################################################
##############################################################################################
## Create topics
dcos package install ${PACKAGE_NAME} --yes --cli
dcos kafka --name=${SERVICE_NAME} topic create
##############################################################################################
##############################################################################################
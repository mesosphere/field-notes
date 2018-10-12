#!/bin/bash
set -e

if [[ "$#" -lt 2 ]]; then
    echo "Not enough arguments."
    echo "Usage: './api-service-account.sh <service-name> <master-ip> -u <usernmae> -p <password>'"
    echo "Alternate usage: './api-service-account.sh <service-name> <master-ip> -t <dcos-auth-token>'"
    echo ""
    echo "For example: './api-service-account.sh path/to/kafka 10.10.10.10 -u admin -p password' will create the following:"
    echo "  A private/public RSA key pair"
    echo "  A service account with the name 'path__to__kafka' (note: no leading slash, all other slashes replaced with '__'.  Dashes are unaffected).  The public key for the service account comes from above"
    echo "  The service account name is also used as the Mesos principal for this framework"
    echo "  The private key, stored as JSON (along with other metadata, including service account name), stored at secret 'path/to/kafka/sa' (note: nested right under the path of the service name, at '<service-name>/sa')"
    echo "  This set of permissions:

                    dcos:mesos:master:framework:role:path__to__kafka-role       create
                    ^ The ability to create/start a framework using Mesos role 'path__to__kafka-role' (the service account name with '-role' appended)

                    dcos:mesos:master:reservation:role:path__to__kafka-role     create
                    ^ The ability to create a reservations using Mesos role 'path__to__kafka-role' (the service account name with '-role' appended)

                    dcos:mesos:master:volume:role:path__to__kafka-role          create
                    ^ The ability to create Mesos volumes using Mesos role 'path__to__kafka-role' (the service account name with '-role' appended)

                    dcos:mesos:master:task:user:nobody                  create
                    ^ The ability for the framework to start Mesos tasks using the Linux user 'nobody'

                    dcos:mesos:master:reservation:principal:path__to__kafka   delete
                    ^ The ability to delete reservations created by the principal 'path__to__kafka'

                    dcos:mesos:master:volume:principal:path__to__kafka        delete
                    ^ The ability to delete Mesos volumes created by the principal 'path__to__kafka'
                    
                    dcos:secrets:default:/path/to/kafka/* full
                    ^ The ability to create and read secrets nested uner /path/to/kafka
                    
                    dcos:secrets:list:default:/path/to/kafka read
                    ^ The ability to get a list of secrets nested under /path/to/kafka
                    
                    dcos:adminrouter:ops:ca:rw full
                    ^ The ability to generate certificates using the DC/OS CA                    
                    
                    dcos:adminrouter:ops:ca:ro full
                    ^ The ability to read CA information"
                    
    exit 1
fi

export SERVICE_NAME="${1}"
shift
export MASTER_IP="${1}"
shift

export USERNAME=""
export PASSWORD=""
export TOKEN=""

export TS=$(date +%s)

while :; do
    case $1 in
        -u|--username)
            if [ -n $2 ]; then
                USERNAME=$2
                shift
            else
                printf "Error: --username requires a username" >&2
                exit 1
            fi
            ;;
        -p|--password)
            if [ -n $2 ]; then
                PASSWORD=$2
                shift
            else
                printf "Error: --password requires a password" >&2
                exit 1
            fi
            ;;
        -t|--token)
            if [ -n $2 ]; then
                TOKEN=$2
                shift
            else
                printf "Error: --token requires a token" >&2
                exit 1
            fi
            ;;
        -T|--tokenfile)
            if [ -n $2 ]; then
                TOKEN=$(cat ${2})
                shift
            else
                printf "Error: --tokenfile requires a filename" >&2
                exit 1
            fi
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [[ "${SERVICE_NAME:0:1}" == "/" ]]; then
    export SERVICE_NAME=${SERVICE_NAME:1}
    echo "Removing leading slash: ${SERVICE_NAME}"
    # exit 0
fi

# If no token, try to get from cluster using username and password
if [[ -z ${TOKEN} ]]; then
    if [[ -z ${USERNAME} ]] && [[ -z ${PASSWORD} ]]; then
        echo "Need to provide username/password or token"
        # print_help
        exit 1
    else
        echo '{"uid": "USERNAME", "password": "PASSWORD"}' > login_request_${TS}.json
        sed -i "s/USERNAME/${USERNAME}/" login_request_${TS}.json
        sed -i "s/PASSWORD/${PASSWORD}/" login_request_${TS}.json

        curl -sk https://${MASTER_IP}/acs/api/v1/auth/login \
            -X POST \
            -H 'content-type:application/json' \
            -d @login_request_${TS}.json \
            > login_token_${TS}.json

        cat login_token_${TS}.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["token"]' > token_${TS}
        rm login_request_${TS}.json
        rm login_token_${TS}.json

        export TOKEN=$(cat token_${TS})
        rm token_${TS}
    fi
else
    echo "Token is ${TOKEN}"
fi

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
export PERMISSION_LIST_FILE="${SERVICE_ACCOUNT}-permissions_${TS}.txt"
export PRIVATE_KEY_FILE="${SERVICE_ACCOUNT}-private_${TS}.pem"
export PUBLIC_KEY_FILE="${SERVICE_ACCOUNT}-public_${TS}.pem"
export SERVICE_ACCOUNT_JSON="${SERVICE_ACCOUNT}-service-account_${TS}.json"
export SERVICE_ACCOUNT_SECRET_JSON="${SERVICE_ACCOUNT}-secret_${TS}.json"
export SERVICE_ACCOUNT_SECRET_FULL_JSON="${SERVICE_ACCOUNT}-secret_${TS}.json.json"

##############################################################################################
## Create service account private / public key pair
# dcos security org service-accounts keypair ${SERVICE_ACCOUNT}-private.pem ${SERVICE_ACCOUNT}-public.pem
echo "Generating service account private/public key pair"
# openssl genrsa -out ${PRIVATE_KEY_FILE} 2048
openssl genpkey -out ${PRIVATE_KEY_FILE} -algorithm RSA -pkeyopt rsa_keygen_bits:2048
openssl rsa -in ${PRIVATE_KEY_FILE} -pubout -out ${PUBLIC_KEY_FILE}

##############################################################################################
## Create service account
# dcos security org service-accounts create -p ${SERVICE_ACCOUNT}-public.pem ${SERVICE_ACCOUNT}

tee ${SERVICE_ACCOUNT_JSON} >> /dev/null <<-'EOF'
{
  "description": "service account `SERVICE_ACCOUNT`",
  "public_key": "PUBLIC_KEY"
}
EOF

# The public key must have escaped endlines
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${SERVICE_ACCOUNT_JSON}
sed -i "s|PUBLIC_KEY|$(sed 's|$|\\\\n|g' ${PUBLIC_KEY_FILE} | tr -d '\n')|g" ${SERVICE_ACCOUNT_JSON}

echo "Creating service account with name ${SERVICE_ACCOUNT}"
## If we get an error creating the service account, it may already exist; bail out cause we don't want to touch it.
curl -fsk https://${MASTER_IP}/acs/api/v1/users/${SERVICE_ACCOUNT} \
    -X PUT \
    -H "authorization: token=${TOKEN}" \
    -H 'content-type:application/json' \
    -d @${SERVICE_ACCOUNT_JSON} 2>/dev/null \
    || (echo "Service account cannot be created or already exists, bailing..." \
        && rm ${PRIVATE_KEY_FILE} ${PUBLIC_KEY_FILE} ${SERVICE_ACCOUNT_JSON} \
        && exit 1)

# exit 0

##############################################################################################
## Create service account secret
# dcos security secrets create-sa-secret --strict ${SERVICE_ACCOUNT}-private.pem ${SERVICE_ACCOUNT} ${SERVICE_ACCOUNT_SECRET}

tee ${SERVICE_ACCOUNT_SECRET_JSON} > /dev/null <<-'EOF'
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

echo "Creating service account secret with name ${SERVICE_ACCOUNT_SECRET}"
## If we get an error creating the service account secret, it may already exist; bail out cause we don't want to touch it.
curl -fsk https://${MASTER_IP}/secrets/v1/secret/default/${SERVICE_ACCOUNT_SECRET} \
    -X PUT \
    -H "authorization: token=${TOKEN}" \
    -H 'content-type:application/json' \
    -d @${SERVICE_ACCOUNT_SECRET_FULL_JSON} \
    || (echo "Service account secret cannot be created or already exists, bailing..." \
        && rm ${PRIVATE_KEY_FILE} ${PUBLIC_KEY_FILE} ${SERVICE_ACCOUNT_JSON} ${SERVICE_ACCOUNT_SECRET_FULL_JSON} ${SERVICE_ACCOUNT_SECRET_JSON} \
        && exit 1)

##############################################################################################
# Create list of permissions
# These may not all be necessary, but it does work.
# The 'role' permissions grant permission to create a reservation - need create only
# The 'principal' permissions grant permission to delete a reservation - need delete only
tee ${PERMISSION_LIST_FILE} > /dev/null <<-'EOF'
dcos:mesos:master:framework:role:SERVICE_ROLE             create
dcos:mesos:master:reservation:role:SERVICE_ROLE           create
dcos:mesos:master:volume:role:SERVICE_ROLE                create
dcos:mesos:master:task:user:nobody                        create
dcos:mesos:master:reservation:principal:SERVICE_ACCOUNT   delete
dcos:mesos:master:volume:principal:SERVICE_ACCOUNT        delete
dcos:secrets:default:/SERVICE_NAME/*                      full
dcos:secrets:list:default:/SERVICE_NAME                   read
dcos:adminrouter:ops:ca:rw                                full
dcos:adminrouter:ops:ca:ro                                full
EOF

sed -i "s|SERVICE_ROLE|${SERVICE_ROLE}|g" ${PERMISSION_LIST_FILE}
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${PERMISSION_LIST_FILE}
sed -i "s|SERVICE_NAME|${SERVICE_NAME}|g" ${PERMISSION_LIST_FILE}

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

  # It is acceptable for the rid to already exist; if it does, we'll get a 409, which gets ignored.
  # Note that we don't bail out on other failures; this should be added later
  echo "Creating permission with rid of '${ESCAPED_PERMISSION_ID}'"
  curl -sk https://${MASTER_IP}/acs/api/v1/acls/${ESCAPED_PERMISSION_ID} \
      -X PUT \
      -H "authorization: token=${TOKEN}" \
      -H 'content-type:application/json' \
      -d @${FLAT_PERMISSION_ID}.json 2>&1 | grep -v 409 || true

  # It is acceptable for the permission to already be granted; if it does, we'll get a 409, which gets ignored.
  # Note that we don't bail out on other failures; this should be added later
  echo "Granting '${PERMISSION_ACTION}' on rid '${ESCAPED_PERMISSION_ID}' to '${SERVICE_ACCOUNT}'"
  curl -sk https://${MASTER_IP}/acs/api/v1/acls/${ESCAPED_PERMISSION_ID}/users/${SERVICE_ACCOUNT}/${PERMISSION_ACTION} \
      -X PUT \
      -H "authorization: token=${TOKEN}" \
      -H 'content-type:application/json' \
      -d @${FLAT_PERMISSION_ID}.json 2>&1 | grep -v 409 || true

  rm ${FLAT_PERMISSION_ID}.json
      
done < ${PERMISSION_LIST_FILE}

rm ${PERMISSION_LIST_FILE}
rm ${PRIVATE_KEY_FILE}
rm ${PUBLIC_KEY_FILE}
rm ${SERVICE_ACCOUNT_JSON}
rm ${SERVICE_ACCOUNT_SECRET_JSON}
rm ${SERVICE_ACCOUNT_SECRET_FULL_JSON}

echo "For service named '${SERVICE_NAME}', created service account '${SERVICE_ACCOUNT}' , with service account secret available at '${SERVICE_ACCOUNT_SECRET}''"
exit 0
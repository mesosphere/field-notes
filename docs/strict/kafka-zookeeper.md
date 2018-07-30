
# Install security CLI
```bash
dcos package install dcos-enterprise-cli --cli --yes
```

# Create key and service account
```bash
export DIRECTORY="dev-2/test"
export NAME="kafka-zookeeper-3"
export PACKAGE_NAME="kafka-zookeeper"
export PACKAGE_VERSION="2.2.0-3.4.11"

export DIRECTORY_S=$(echo ${DIRECTORY} | sed "s|/|__|g")
export NAME_S=$(echo ${NAME} | sed "s|/|__|g")

export SERVICE_NAME="${DIRECTORY}/${NAME}"
export SERVICE_ACCOUNT="${DIRECTORY_S}__${NAME_S}_sa"
export SERVICE_ACCOUNT_SECRET="${SERVICE_NAME}/sa"
export KEYFILE="${SERVICE_ACCOUNT}"
export PACKAGE_OPTIONS_FILE="${DIRECTORY_S}__${NAME_S}-options.json"
export PERMISSION_LIST_FILE="${DIRECTORY_S}__${NAME_S}-permissions"
export SERVICE_ROLE="${DIRECTORY_S}__${NAME_S}-role"
export PRINCIPAL="${DIRECTORY_S}__${NAME_S}"
export TRIMMED_NAME="$(echo ${SERVICE_NAME} | sed 's|/||g')"
export ENDPOINT_FILE="${DIRECTORY_S}__${NAME_S}-endpoints"

dcos security org service-accounts keypair ${KEYFILE}-private.pem ${KEYFILE}-public.pem
dcos security org service-accounts create -p ${KEYFILE}-public.pem ${SERVICE_ACCOUNT}
dcos security secrets create-sa-secret --strict ${KEYFILE}-private.pem ${SERVICE_ACCOUNT} ${SERVICE_ACCOUNT_SECRET}

tee ${PACKAGE_OPTIONS_FILE} <<-'EOF'
{
  "service": {
    "name": "SERVICE_NAME",
    "service_account":"SERVICE_ACCOUNT",
    "service_account_secret": "SERVICE_ACCOUNT_SECRET",
    "virtual_network_enabled": true
  }
}
EOF

sed -i "s|SERVICE_ACCOUNT_SECRET|${SERVICE_ACCOUNT_SECRET}|g" ${PACKAGE_OPTIONS_FILE}
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${PACKAGE_OPTIONS_FILE}
sed -i "s|SERVICE_NAME|${SERVICE_NAME}|g" ${PACKAGE_OPTIONS_FILE}

tee ${PERMISSION_LIST_FILE} <<-'EOF'
dcos:mesos:master:framework:role:SERVICE_ROLE       create
dcos:mesos:master:reservation:role:SERVICE_ROLE     create
dcos:mesos:master:volume:role:SERVICE_ROLE          create
dcos:mesos:master:task:user:nobody                  create
dcos:mesos:master:reservation:principal:PRINCIPAL   create
dcos:mesos:master:reservation:principal:PRINCIPAL   delete
dcos:mesos:master:volume:principal:PRINCIPAL        create
dcos:mesos:master:volume:principal:PRINCIPAL        delete
EOF

sed -i "s|SERVICE_ROLE|${SERVICE_ROLE}|g" ${PERMISSION_LIST_FILE}
sed -i "s|PRINCIPAL|${PRINCIPAL}|g" ${PERMISSION_LIST_FILE}

while read p; do
dcos security org users grant ${SERVICE_ACCOUNT} $p
done < ${PERMISSION_LIST_FILE}

dcos package install ${PACKAGE_NAME} --package-version=${PACKAGE_VERSION} --options=${PACKAGE_OPTIONS_FILE} --yes --app

echo "zookeeper-0-server.${TRIMMED_NAME}.autoip.dcos.thisdcos.directory:1140,zookeeper-1-server.${TRIMMED_NAME}.autoip.dcos.thisdcos.directory:1140,zookeeper-2-server.${TRIMMED_NAME}.autoip.dcos.thisdcos.directory:1140" > ${ENDPOINT_FILE}
```

# Required permissions
```
dcos:mesos:master:framework:role:<role>
  create
dcos:mesos:master:reservation:role:<role>
  create
dcos:mesos:master:volume:role:<role>
  create
dcos:mesos:master:task:user:nobody
  create
dcos:mesos:master:reservation:principal:<service-account-id>
  create
  delete
dcos:mesos:master:volume:principal:<service-account-id>
  create
  delete
```
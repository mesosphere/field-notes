
# Install security CLI
```bash
dcos package install dcos-enterprise-cli --cli --yes
```

# Create key and service account
```bash
export DIRECTORY="dev-2/test"
export NAME="kafka-4"
export PACKAGE_NAME="kafka"
export PACKAGE_VERSION="2.3.0-1.1.0"

export ZK_DIRECTORY="dev-2/test"
export ZK_NAME="kafka-zookeeper-3"
export ZK_SHORT=$(echo ${ZK_DIRECTORY}${ZK_NAME} | sed "s|/||g")
export ZK_URI="zookeeper-0-server.${ZK_SHORT}.autoip.dcos.thisdcos.directory:1140,zookeeper-1-server.${ZK_SHORT}.autoip.dcos.thisdcos.directory:1140,zookeeper-2-server.${ZK_SHORT}.autoip.dcos.thisdcos.directory:1140"

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

echo zookeeper-0-server.TRIMMED_NAME.autoip.dcos.thisdcos.directory:1140,zookeeper-1-server.TRIMMED_NAME.autoip.dcos.thisdcos.directory:1140,zookeeper-2-server.TRIMMED_NAME.autoip.dcos.thisdcos.directory:1140 | sed "s|TRIMMED_NAME|${TRIMMED_NAME}|g" > ${ENDPOINT_FILE}
```

# Create topics
```bash
dcos kafka --name=${SERVICE_NAME} topic create
```
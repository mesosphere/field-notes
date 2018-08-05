This is a parameterized way to install Kafka-Zookeeper in strict mode (for use with Kafka)

*This is to be used to stand up ZK for [kafka-custom-zk](kafka-custom-zk.md)*

# Install security CLI
```bash
dcos package install dcos-enterprise-cli --cli --yes
```

# Create key and service account
```bash
# Do not specify a leading slash ('/')
export SERVICE_NAME="dev-2/path-to/kafka-zk-4"
export PACKAGE_NAME="kafka-zookeeper"
export PACKAGE_VERSION="2.2.0-3.4.11"

# principal is SERVICE_NAME with slashes replaced with '__'
export PRINCIPAL=$(echo ${SERVICE_NAME} | sed "s|/|__|g")

# dns is generated from SERVICE_NAME with slashes removed
export SERVICE_DNS_NAME="$(echo ${SERVICE_NAME} | sed 's|/||g')"

export SERVICE_ACCOUNT="${PRINCIPAL}_sa"
export SERVICE_ACCOUNT_SECRET="${SERVICE_NAME}/sa"
export SERVICE_ROLE="${PRINCIPAL}-role"

# Used for filenames
export PACKAGE_OPTIONS_FILE="${PRINCIPAL}-options.json"
export PERMISSION_LIST_FILE="${PRINCIPAL}-permissions.txt"
export ENDPOINT_FILE="${PRINCIPAL}-endpoints.txt"

dcos security org service-accounts keypair ${PRINCIPAL}-private.pem ${PRINCIPAL}-public.pem
dcos security org service-accounts create -p ${PRINCIPAL}-public.pem ${SERVICE_ACCOUNT}
dcos security secrets create-sa-secret --strict ${PRINCIPAL}-private.pem ${SERVICE_ACCOUNT} ${SERVICE_ACCOUNT_SECRET}

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

# These may not all be necessary, but it does work.
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

echo "zookeeper-0-server.${SERVICE_DNS_NAME}.autoip.dcos.thisdcos.directory:1140,zookeeper-1-server.${SERVICE_DNS_NAME}.autoip.dcos.thisdcos.directory:1140,zookeeper-2-server.${SERVICE_DNS_NAME}.autoip.dcos.thisdcos.directory:1140" > ${ENDPOINT_FILE}
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
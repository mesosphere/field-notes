This is a parameterized way to install Marathon-LB in strict mode.

# Install security CLI
```bash
dcos package install dcos-enterprise-cli --cli --yes
```

# Create key and service account
```bash
#!/bin/bash

## Do not specify a leading slash ('/')
export SERVICE_NAME="marathon-lb"
# export SERVICE_NAME="prod-app/stage/marathon-lb"
export PACKAGE_NAME="marathon-lb"
export PACKAGE_VERSION="1.12.2"

export MARATHON_LOCATION="/"
export HAPROXY_GROUP="external"

# principal is SERVICE_NAME with slashes replaced with '__'
export PRINCIPAL=$(echo ${SERVICE_NAME} | sed "s|/|__|g")

export SERVICE_ACCOUNT_SECRET="${SERVICE_NAME}/sa"

# Used for filenames
export PACKAGE_OPTIONS_FILE="${PRINCIPAL}-options.json"
export PERMISSION_LIST_FILE="${PRINCIPAL}-permissions.txt"

## Create service account and secret
dcos security org service-accounts keypair ${PRINCIPAL}-private.pem ${PRINCIPAL}-public.pem
dcos security org service-accounts create -p ${PRINCIPAL}-public.pem ${PRINCIPAL}
dcos security secrets create-sa-secret --strict ${PRINCIPAL}-private.pem ${PRINCIPAL} ${SERVICE_ACCOUNT_SECRET}

## Create options file
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

## Create permissions file
tee ${PERMISSION_LIST_FILE} <<-'EOF'
dcos:service:marathon:marathon:services:MARATHON_LOCATION read
dcos:service:marathon:marathon:admin:events read
EOF

## Add permissions
sed -i "s|MARATHON_LOCATION|${MARATHON_LOCATION}|g" ${PERMISSION_LIST_FILE}
while read p; do
dcos security org users grant ${PRINCIPAL} $p
done < ${PERMISSION_LIST_FILE}

dcos package install ${PACKAGE_NAME} --package-version=${PACKAGE_VERSION} --options=${PACKAGE_OPTIONS_FILE} --yes --app
```
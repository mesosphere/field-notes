# HDFS

```bash

export SERVICE_NAME="test/hdfs"
export SERVICE_ACCOUNT="test-hdfs-sa"
export SERVICE_ACCOUNT_SECRET=${SERVICE_NAME}/sa
export KEYFILE=${SERVICE_ACCOUNT}
export CONFIGFILE="test-hdfs-options.json"
export HDFS_VERSION="2.2.0-2.6.0-cdh5.11.0"
export HDFS_ROLE="test__hdfs-role"
export PRINCIPAL="test_hdfs"

dcos package install dcos-enterprise-cli --cli --yes
dcos security org service-accounts keypair ${KEYFILE}-private.pem ${KEYFILE}-public.pem
dcos security org service-accounts create -p ${KEYFILE}-public.pem ${SERVICE_ACCOUNT}
dcos security secrets create-sa-secret --strict ${KEYFILE}-private.pem ${SERVICE_ACCOUNT} ${SERVICE_ACCOUNT_SECRET}

dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:task:user:nobody create
dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:task:app_id:${SERVICE_NAME} create
dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:framework:role:${HDFS_ROLE} create
dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:reservation:role:d${HDFS_ROLE} create
dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:reservation:principal:${PRINCIPAL} create
dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:reservation:principal:${PRINCIPAL} delete
dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:volume:role:${HDFS_ROLE} create
dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:volume:principal:${PRINCIPAL} create
dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:volume:principal:${PRINCIPAL} delete

tee ${CONFIGFILE} <<-'EOF'
{
  "service": {
    "name": "SERVICE_NAME",
    "service_account":"SERVICE_ACCOUNT",
    "service_account_secret": "SERVICE_ACCOUNT_SECRET"
  }
}
EOF

sed -i "s|SERVICE_ACCOUNT_SECRET|${SERVICE_ACCOUNT_SECRET}|g" ${CONFIGFILE}
sed -i "s|SERVICE_ACCOUNT|${SERVICE_ACCOUNT}|g" ${CONFIGFILE}
sed -i "s|SERVICE_NAME|${SERVICE_NAME}|g" ${CONFIGFILE}

# Install the CLI
dcos package install --package-version=${HDFS_VERSION} hdfs --cli --yes

# Install the package
dcos package install --options=${CONFIGFILE} --package-version=${HDFS_VERSION} hdfs --app --yes
```

```bash
dcos:mesos:master:task:user:nobody create
dcos:mesos:master:task:app_id:${SERVICE_NAME} create
dcos:mesos:master:framework:role:${HDFS_ROLE} create
dcos:mesos:master:reservation:role:d${HDFS_ROLE} create
dcos:mesos:master:reservation:principal:${PRINCIPAL} create
dcos:mesos:master:reservation:principal:${PRINCIPAL} delete
dcos:mesos:master:volume:role:${HDFS_ROLE} create
dcos:mesos:master:volume:principal:${PRINCIPAL} create
dcos:mesos:master:volume:principal:${PRINCIPAL} delete
```

```ref
dcos:mesos:master:task:user:nobody create
dcos:mesos:master:task:app_id:/dev/hdfs create
dcos:mesos:master:framework:role:dev__hdfs-role create
dcos:mesos:master:reservation:role:dev__hdfs-role create
dcos:mesos:master:reservation:principal:dev_hdfs create
dcos:mesos:master:reservation:principal:dev_hdfs delete
dcos:mesos:master:volume:role:dev__hdfs-role create
dcos:mesos:master:volume:principal:dev_hdfs create
dcos:mesos:master:volume:principal:dev_hdfs delete

-H "Authorization: token=$(dcos config show core.dcos_acs_token)" $(dcos config show core.dcos_url)/acs/api/v1/acls/dcos:mesos:master:framework:role:hdfs-role/users/<service-account-id>/create
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=$(dcos config show core.dcos_acs_token)" $(dcos config show core.dcos_url)/acs/api/v1/acls/dcos:mesos:master:reservation:role:hdfs-role/users/<service-account-id>/create
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=$(dcos config show core.dcos_acs_token)" $(dcos config show core.dcos_url)/acs/api/v1/acls/dcos:mesos:master:volume:role:hdfs-role/users/<service-account-id>/create
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=$(dcos config show core.dcos_acs_token)" $(dcos config show core.dcos_url)/acs/api/v1/acls/dcos:mesos:master:task:user:nobody/users/<service-account-id>/create
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=$(dcos config show core.dcos_acs_token)" $(dcos config show core.dcos_url)/acs/api/v1/acls/dcos:mesos:master:reservation:principal:<service-account-id>/users/<service-account-id>/delete
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=$(dcos config show core.dcos_acs_token)" $(dcos config show core.dcos_url)/acs/api/v1/acls/dcos:mesos:master:volume:principal:<service-account-id>/users/<service-account-id>/delete
```
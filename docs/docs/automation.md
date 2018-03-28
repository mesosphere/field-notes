---
---

This document details some of the automation that can be used to create a cluster as code.

## LDAP

### Export LDAP Configuration (JSON) from a configured DC/OS Cluster
```bash
# Set up authorization and env variables
export CLUSTER=$(dcos config show core.dcos_url)
export CLUSTER_IP=$(echo ${CLUSTER} | awk -F'/' '{print $NF}')
export TOKEN=$(dcos config show core.dcos_acs_token)

# Get cluster CA certificate
curl http://${CLUSTER_IP}/ca/dcos-ca.crt -o ${CLUSTER_IP}.ca.crt

# View current LDAP configuration
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "Authorization: token=${TOKEN}" \
    ${CLUSTER}/acs/api/v1/ldap/config

# Save current LDAP configuration to json
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "Authorization: token=${TOKEN}" \
    ${CLUSTER}/acs/api/v1/ldap/config > ldap-${CLUSTER_IP}.json
```

### Import LDAP Configuration (JSON) into a DC/OS Cluster
```bash
# Set up authorization and env variables
export CLUSTER=$(dcos config show core.dcos_url)
export CLUSTER_IP=$(echo ${CLUSTER} | awk -F'/' '{print $NF}')
export TOKEN=$(dcos config show core.dcos_acs_token)

# Get cluster CA certificate
curl http://${CLUSTER_IP}/ca/dcos-ca.crt -o ${CLUSTER_IP}.ca.crt

# Set LDAP configuration
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X PUT \
    -d @ldap-${CLUSTER_IP}.json \
    ${CLUSTER}/acs/api/v1/ldap/config
```

### Test LDAP Connection
```bash
# Set up authorization and env variables
export CLUSTER=$(dcos config show core.dcos_url)
export CLUSTER_IP=$(echo ${CLUSTER} | awk -F'/' '{print $NF}')
export TOKEN=$(dcos config show core.dcos_acs_token)

# Get cluster CA certificate
curl http://${CLUSTER_IP}/ca/dcos-ca.crt -o ${CLUSTER_IP}.ca.crt

# Setup env variables for json
export USERNAME="Justin.Lee"
export PASSWORD="password123"

# Generate json
tee ldap-test.json <<-'EOF'
{
    "uid": "USERNAME",
    "password": "PASSWORD"
}
EOF

sed -i "s/USERNAME/${USERNAME}/; s/PASSWORD/${PASSWORD}/" ldap-test.json

# Test connection
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X POST \
    -d @ldap-test.json \
    ${CLUSTER}/acs/api/v1/ldap/config/test
```

You should see a result that looks like this:
```json
{
  "description": "Directory back-end reached and all tests passed.",
  "code": "TEST_PASSED"
}
```

## Import a user from LDAP
You can use the API to import a user into DC/OS.  Note that this user will by default have no permissions (they will be able to authenticate but not access anything)
```bash
# Set up authorization and env variables
export CLUSTER=$(dcos config show core.dcos_url)
export CLUSTER_IP=$(echo ${CLUSTER} | awk -F'/' '{print $NF}')
export TOKEN=$(dcos config show core.dcos_acs_token)

# Get cluster CA certificate
curl http://${CLUSTER_IP}/ca/dcos-ca.crt -o ${CLUSTER_IP}.ca.crt

# Set up env variable for user to be imported
export USERNAME=Justin.Lee

# Generate json
tee ldap-import.json <<-'EOF'
{
    "username": "USERNAME"
}
EOF

sed -i "s/USERNAME/${USERNAME}/" ldap-import.json

# 
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X POST \
    -d @ldap-import.json \
    ${CLUSTER}/acs/api/v1/ldap/importuser
```

### Import a group from LDAP
You can also use the API to import a user into DC/OS.  This will import all users in that group in LDAP into a DC/OS group of the same name.  Note that this group will by default have no permissions (they will be able to authenticate but not access anything).
```bash
# Set up authorization and env variables
export CLUSTER=$(dcos config show core.dcos_url)
export CLUSTER_IP=$(echo ${CLUSTER} | awk -F'/' '{print $NF}')
export TOKEN=$(dcos config show core.dcos_acs_token)

# Get cluster CA certificate
curl http://${CLUSTER_IP}/ca/dcos-ca.crt -o ${CLUSTER_IP}.ca.crt

# Set up env variable for user to be imported
export GROUPNAME=Justin.Lee

# Generate json
tee ldap-group-import.json <<-'EOF'
{
    "groupname": "GROUPNAME"
}
EOF

sed -i "s/GROUPNAME/${GROUPNAME}/" ldap-group-import.json

# Trigger the import
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X POST \
    -d @ldap-group-import.json \
    ${CLUSTER}/acs/api/v1/ldap/importgroup
```
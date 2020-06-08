# Cockroach state clear for upgrades



## Backup Cockroach

```bash
sudo /opt/mesosphere/bin/cockroach --certs-dir=/run/dcos/pki/cockroach --host=$(/opt/mesosphere/bin/detect_ip) dump iam > backup.sql
```

## Remove CockroachDB state **OUTAGE**

**OUTAGE**
This will cause a short period where no new user/service accounts will be able to get token or perfrom an auth function

On all master nodes

```bash
sudo sytemctl stop dcos-cockroach
sudo rm -rf /var/lib/dcos/cockroach/*

# can be done on just one
/opt/mesosphere/bin/dcos-shell zkCli.sh -server 127.0.0.1:2181 delete /cockroach/nodes

sudo systemctl start dcos-cockroach
```

## Restore IAM data

On one master node run commands.
In some versions the second command may have an issue compaing iam alreday exists, this should be okay.
Different versions of cockroach made the dump create or not create the iam table.

```bash
sudo /opt/mesosphere/bin/cockroach sql --certs-dir=/run/dcos/pki/cockroach --host=$(/opt/mesosphere/bin/detect_ip)
CREATE DATABASE iam;
sudo /opt/mesosphere/bin/cockroach sql --certs-dir=/run/dcos/pki/cockroach --host=$(/opt/mesosphere/bin/detect_ip) --database=iam < backup.sql
```

# Creating file-based secrets using the API

```bash
curl -X PUT \
  --cacert dcos-ca.crt \
  -H "authorization: token=$(dcos config show core.dcos_acs_token)" \
  -H "content-type: application/octet-stream" \
  --data-binary @<filename> \
  $(dcos config show core.dcos_url)/secrets/v1/secret/path/to/secret
```

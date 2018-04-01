---
---

# Multitenant Resource Isolation Instructions

### OSS Marathon-on-Marathon
Create a JSON file mom.json, with at least these parameters:

```json
{
"service": {
    "name": "marathon-dev"
},
"marathon": {
    "default-accepted-resource-roles": "dev,*",
    "framework-name": "marathon-dev",
    "mesos-role": "dev",
    "mesos-user": "marathon-dev-principal"
}
}
```

Optionally, make these modifications:
* Replace `dev` with the correct role (e.g., `prod`)
* If you want the MoM instance to only be able to use resources *reserved* for your role, specify `dev` (or your correct role).
* If you want the MoM instance to also be able to use *unreserved* resources (in addition to being able to use *reserved* resources), specify `dev,*` (or your correct role and `,*` comma separated).

Use it to install the latest version of MoM, using this command:

```bash
dcos package install marathon --options=mom.json --yes
```

### EE Marathon-on-Marathon

Currently, MoM EE can only be installed with an image provided by Mesosphere.  Please contact Mesosphere for guidance.
* TODO

### Configuring Access to EE MoM

Currently, MoM EE can only be installed with an image provided by Mesosphere.  Please contact Mesosphere for guidance.
* TODO

### Configuring Access within EE MoM

Currently, MoM EE can only be installed with an image provided by Mesosphere.  Please contact Mesosphere for guidance.
* TODO

### Static Reservations: Full Node
* TODO

### Static Reservations: Partial Node
* TODO

### Dynamic Reservations
* TODO

### Configuring Quotas
* TODO

### Configuring Marathon-LB with MoM
* TODO

### Configuring Edge-LB with MoM
* TODO

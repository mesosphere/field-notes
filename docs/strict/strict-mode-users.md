
# Strict Users
## Basic concepts:
* Each host has an /etc/passwd, and each container image (generally) also has the an /etc/passwd.  The users in these may or may not be the same (usually depends on what the base OS is, and what has been added).  These two files are used for user lookups in different contexts.
* Each container has a primary process (and potentially child processes), which is usually indicated in the `ENTRYPOINT` or `CMD` of the Docker file, and may be overridden in the Marathon app definition with the `.cmd` field.
  * This primary process is run by some user.  Specifically, it is run by some (numerical) **uid**, which may or may not map to an actual username, depending on your context.  The way the **uid** is determined is dependent on the runtime and environment.
* A Docker image *may* have a user associated with it (indicated by `"user":"nobody"` in the output of `docker inspect <imagename>` or `USER nobody` in a Dockerfile)
* A Marathon app may specify various URIs, which are artifacts (files, tarballs, etc.) that are pulled into the container before it starts.  Generally, if these are extractable, they will be extracted (`.fetch[N].extract` flag set to `true` or `false`, default `true`)
* A Marathon app may specify various types of volume mounts.  I'm primarily focused on host volumes here, but this should generally apply to all volume types.
* A Marathon app may run a Docker image in the Mesos runtime or the Docker runtime
  * If using the Docker runtime, you may specify arbitrary docker parameters at `.container.docker.parameters` (e.g., `.container.docker.parameters: [{"key": "user", "value": "guest"}]`)
  * If using the Mesos runtime, you may specify a user at `.user`

## Example environment:
* (CentOS) host /etc/passwd:
```bash
root:x:0:0:root:/root:/bin/bash
nobody:x:99:99:Nobody:/:/sbin/nologin
centos:x:1000:1000:Cloud User:/home/centos:/bin/bash
```

* (Alpine) container /etc/passwd:
```bash
root:x:0:0:root:/root:/bin/ash
guest:x:405:100:guest:/dev/null:/sbin/nologin
nobody:x:65534:65534:nobody:/:/sbin/nologin
```


## Docker runtime (in strict):
* Process user:
  * If a Docker parameter is specified indicating user, then Docker does a lookup for that user in the container image `/etc/passwd` to determine the **uid** for the primary container process.  
    * E.g.: If the Marathon app has `.container.docker.parameters: [{"key": "user", "value": "guest"}]`, then the container process will be run as uid 405
  * Otherwise, if a user is specified in the image, then Docker does a lookup for that user in the container image `/etc/passwd` to determine the **uid** for the primary container process.
    * E.g.: If `USER nobody` was specified in the Dockerfile for the image, then the container process will be run as uid 65534
  * Otherwise, **uid** of `0` is used `root` is used for the primary process (not sure if this looks up the user `root` or just uses 0, and it doesn't really matter)
    * E.g.: If the Docker image doesn't have a specified user and the Marathon app doesn't have a specified user,  then the container process will be run as uid 0
* URIs:
  * Mesos does a userid lookup for `nobody` on the **host** `/etc/passwd`, and uses that to fetch and potentially extract URIs.
    * E.g.: All fetched files will be created with an owner of uid 99, even though uid 99 doesn't exist in the container.
* Volume mounts:
  * If a volume is mounted into the container, and the container process performs actions on that volume (read/write/execute), the **uid** of the container process is used for those actions, regardless of whether that uid exists on the host.
    * E.g.: If `/var/log/test` is mounted into the container at `/mnt/mesos/sandbox/test` (containerpath of `test`), and a file is created in the container at `/mnt/mesos/sandbox/test/hello`, that file will be created on the host filesystem at `/var/log/test/hello` with a uid of 405, 65534, or 0 (based on the above container process determination)
* Summary (permissive -> strict):
  * If your images and marathon apps have no specified user, there's minimal behavior change from permissive to strict; just be aware that fetched files may have an unexpected uid (whatever uid is `nobody` on the host filesystem)
  * Not unique to strict, but if you're mounting volumes into the container, ensure that your process uid has permissions to perform actions on those volumes.

## Mesos runtime:
* Process user:
  * If a user is specified in the Marathon app, then Mesos will do a userid lookup or that user on the **host** `/etc/passwd` and use that for the container process, *even if that userid does not exist in the container*.  Additionally, you'll need to add the permission `dcos:mesos:master:task:user:<username> create` to the `dcos_marathon` service account.
    * E.g., If the Marathon app has `.user: centos` without the necessary permission added to `dcos_marathon`, the process will fail to start.
    * E.g., If the Marathon app has `.user: centos` with the necessary permission, then the process will be run as uid 1000.
    * E.g., If the Marathon app has specified user that does not exist on the host `/etc/passwd`, then the process will fail to start.
  * If neither the image nor the Marathon specify a user, then Mesos will do userid lookup for `nobody` on the **host** `/etc/passwd` and use that for the process, *even if that userid does not exist in the container*.
    * E.g., The process will be run as uid 99, even if uid 99 does not exist in the container.
  * You can specify `root` as the user to use in the Marathon app definition, but that requires that `dcos_marathon` be granted permission to create tasks as `root`, clusterwide.
    * E.g., The process will be run as uid 0, but this will require a clusterwide permission for marathon.
* URIs:
  * Mesos does a userid lookup for `nobody` on the **host** `/etc/passwd`, and uses that to fetch and potentially extract URIs.
    * E.g.: All fetched files will be created with an owner of uid 99, even though uid 99 doesn't exist in the container.
* Volume mounts:
  * If a volume is mounted into the container, and the container process performs actions on that volume (read/write/execute), the **uid** of the container process is used for those actions.  That **uid** will generally exist on the host (since it was initially looked up on the host).
    * E.g.: If `/var/log/test` is mounted into the container at `/mnt/mesos/sandbox/test` (containerpath of `test`), and a file is created in the container at `/mnt/mesos/sandbox/test/hello`, that file will be created on the host filesystem at `/var/log/test/hello` with a uid of 1000, 99, or 0 (based on the above container process determination)
* Summary (permissive -> strict):
  * Process uid concerns:
    * You should be aware of what uid `nobody` matches on your host filesystem (for example, 99 in most CentOS environments), and ensure that that uid exists in containers and can run the primary container process successfully.
    * Alternately, as an interim solution, for containers that support a non-root process user, you can do the following without modifying the container:
      * Determine what uid in the container can run the container process (such as '405' in the above)
      * Create a user on the host filesystem(s) with the equivalent uid (e.g., create user `alpineguest` or `alpine` with uid 405 on the host filesystems)
      * Configure the marathon app to run with your custom user (e.g. `alpineguest` or `alpine`)
      * Ensure `dcos_marathon` has the relevant permissions added to run the app (e.g. `dcos:mesos:master:task:user:alpineguest create` or `dcos:mesos:master:task:user:alpine create`)
    * Alternately, for containers that must be run as root:
      * Configure the marathon app to run with the root user
      * Ensure `dcos_marathon` has the relevant permissions added to run the app (e.g. `dcos:mesos:master:task:user:root create`)
  * Be aware that fetched files will have the host filesystem `nobody` uid, even though that uid may not exist in the container
  * If you're mounting volumes into the container, ensure that your process uid has permissions to perform actions on those volumes.
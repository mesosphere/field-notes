When you're running an app on your cluster and need your `stdout` and `stderr` files to be way larger than the standard 2MB, you can use the 
following lines of code in your JSON app definition file to achieve the larger files:

```
"env": {
    "CONTAINER_LOGGER_LOGROTATE_MAX_STDOUT_SIZE": "20MB",
    "CONTAINER_LOGGER_LOGROTATE_STDOUT_OPTIONS": "rotate 9",
    "CONTAINER_LOGGER_LOGROTATE_MAX_STDERR_SIZE": "20MB",
    "CONTAINER_LOGGER_LOGROTATE_STDERR_OPTIONS": "rotate 9"
  }
```

Creating your application/service with this addition will take care of always having tiny files when you actually need nice and big logfiles.

**!!NOTE!! always be mindful of using this since it can fill up your filesystem if you don't pay attention.**

Another option would be to change the `/opt/mesosphere/etc/mesos-slave-modules/journal_logger_modules.json` file to change these settings on a system wide level.
I wouldn't recommend this due to the above risk to run out of diskspace and risking downtime.

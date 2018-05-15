---
---

This is meant to be a rolling FAQ for DC/OS users.  This is very incomplete.

This simple ip-detect script that should almost always work:

```bash
#!/bin/bash
ip route get 8.8.8.8 | awk 'NR==1{print $NF}'
```

Things to try/check when standing up or troubleshooting a DC/OS cluster:

* Make sure that your ip-detect script returns the expected IP address (and that this IP address actually exists as an IP address on the system)

    `bash /opt/mesosphere/bin/detect_ip`

    `ip a | grep $(/opt/mesosphere/bin/detect_ip)`

    ```bash
    $ bash /opt/mesosphere/bin/detect_ip
        192.168.10.31

    $ ip a | grep $(/opt/mesosphere/bin/detect_ip)
        inet 192.168.10.31/24 brd 192.168.10.255 scope global eth0
    ```

* Check that time is reporting healthy:

    `ENABLE_CHECK_TIME=true /opt/mesosphere/bin/check-time`

    ```bash
    $ ENABLE_CHECK_TIME=true /opt/mesosphere/bin/check-time
    Checking whether time is synchronized using the kernel adjtimex API.
    Time can be synchronized via most popular mechanisms (ntpd, chrony, systemd-timesyncd, etc.)
    Time is in sync!
    ```

* Check that exhibitor is healthy (should return with JSON indicating all of your masters, all with `"description":"serving"` and `"code":3`

    `curl -s $(ip route get 8.8.8.8 | awk 'NR==1{print $NF}'):8181/exhibitor/v1/cluster/status`

    ```bash
    $ curl -s $(ip route get 8.8.8.8 | awk 'NR==1{print $NF}'):8181/exhibitor/v1/cluster/status

    [{"code":3,"description":"serving","hostname":"192.168.10.31","isLeader":false},{"code":3,"description":"serving","hostname":"192.168.10.32","isLeader":true},{"code":3,"description":"serving","hostname":"192.168.10.33","isLeader":false}]
    ```

* If you're on Enterprise DC/OS, check that cockroachdb is healthy (look for ranges_underreplicated to be 0)

    `curl -skL 127.0.0.1:8090/_status/vars | grep ranges_underreplicated`

    ```bash
    $ curl -skL 127.0.0.1:8090/_status/vars | grep ranges_underreplicated
    # HELP ranges_underreplicated Number of ranges with fewer live replicas than the replication target
    # TYPE ranges_underreplicated gauge
    ranges_underreplicated{store="2"} 0
    ```

* Verify that spartan is healthy

    `ping -c2 -W1 ready.spartan`

    ```bash
    $ ping -c2 -W1 ready.spartan

    PING ready.spartan (127.0.0.1) 56(84) bytes of data.
    64 bytes from localhost (127.0.0.1): icmp_seq=1 ttl=64 time=0.031 ms
    64 bytes from localhost (127.0.0.1): icmp_seq=2 ttl=64 time=0.030 ms

    --- ready.spartan ping statistics ---
    2 packets transmitted, 2 received, 0% packet loss, time 1000ms
    rtt min/avg/max/mdev = 0.030/0.030/0.031/0.005 ms
    ```

* Verify that Mesos is healthy (look for `overlay/log/recovered` and `registrar/log/recovered` to both be 1):


    `curl -s $(ip route get 8.8.8.8 | awk 'NR==1{print $NF}'):5050/metrics/snapshot | tr ',' '\n' | grep recovered`

    ```bash
    $ curl -s $(ip route get 8.8.8.8 | awk 'NR==1{print $NF}'):5050/metrics/snapshot | tr ',' '\n' | grep recovered
    "overlay\/log\/recovered":1.0
    "registrar\/log\/recovered":1.0
    ```

* Verify that mesos-dns is healthy

    `ping -c2 -W1 leader.mesos`

    ```bash
    $ ping -c2 -W1 leader.mesos
    PING leader.mesos (192.168.10.32) 56(84) bytes of data.
    64 bytes from master-asus-32 (192.168.10.32): icmp_seq=1 ttl=64 time=3.64 ms
    64 bytes from master-asus-32 (192.168.10.32): icmp_seq=2 ttl=64 time=2.12 ms

    --- leader.mesos ping statistics ---
    2 packets transmitted, 2 received, 0% packet loss, time 1000ms
    rtt min/avg/max/mdev = 2.124/2.886/3.648/0.762 ms
    ```

* Verify that Marathon is healthy

    `curl -skL $(ip route get 8.8.8.8 | awk 'NR==1{print $NF}'):8080/v2/leader`

    ```bash
    $ curl -skL $(ip route get 8.8.8.8 | awk 'NR==1{print $NF}'):8080/v2/leader
    3{"leader":"192.168.10.33:8080"}
    ```

* See if the UI responds to curl:

    `curl $(ip route get 8.8.8.8 | awk 'NR==1{print $NF}') -kL | head -c300`

    ```bash
    $ curl $(ip route get 8.8.8.8 | awk 'NR==1{print $NF}') -skL | head -c300
    <!DOCTYPE html> <html lang=en class=no-js> <head> <title> Mesosphere DC/OS </title> <meta charset=utf-8> <meta http-equiv=X-UA-Compatible content="IE=edge,chrome=1"> <meta name=title content="Mesosphere DC/OS"><!--[if lt IE 9]>
    <script src="http://html5shim.googlecode.com/svn/trunk/html5.js">
    ```


Q: I'm having issues installing DC/OS.  Can you help me troubleshoot?

A1: Things to check with every installation:
* Did you verify that your ntp is properly synchronized and working?
* Can you verify that if you copy the ip-detect script to all of your nodes, and run it on each node, it properly responds with an IP address that is reachable from all nodes?
* Can you verify that the output of ip-detect run on your masters matches the IP address(es) given in your master_list in your config.yaml
* For troubleshooting, it is always helpful to provide the config.yaml that you're using
* Look at logs, specifically journalctl logs.  Look at the output of `sudo systemctl list-units dcos-*` (don't forget the asterisk) on each node to see what systemd units are failing or not failing.  You should see between 15 and 25 systemd units on all nodes.
* If you identify that a lot of systemd units are failing, look at the journal logs for these units first:
    * journalctl -fu dcos-spartan (this has been replaced by `dcos-net` in DC/OS 1.11.x and above)
    * journalctl -fu dcos-exhibitor
    * journalctl -fu dcos-mesos-master (on masters)

A2: What installer did you use?  Try using the advanced installer.  It's a bit easier to use and a lot easier to troubleshoot and understand than the CLI and GUI installers.  A quick walkthrough of a very basic installation is available here: [Distributed DC/OS Cluster Setup](../distributed-setup.md)

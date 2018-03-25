This is meant to be a rolling FAQ for DC/OS users.  This is very incomplete.

Q: I'm having issues installing DC/OS.  Can you help me troubleshoot?

A1: Things to check with every installation:
* Did you verify that your ntp is properly synchronized and working?
* Can you verify that if you copy the ip-detect script to all of your nodes, and run it on each node, it properly responds with an IP address that is reachable from all nodes?
* Can you verify that the output of ip-detect run on your masters matches the IP address(es) given in your master_list in your config.yaml
* For troubleshooting, it is always helpful to provide the config.yaml that you're using
* Look at logs, specifically journalctl logs.  Look at the output of `sudo systemctl list-units dcos-*` (don't forget the asterisk) on each node to see what systemd units are failing or not failing.  You should see between 15 and 25 systemd units on all nodes.
* If you identify that a lot of systemd units are failing, look at the journal logs for these units first:
    * journalctl -fu dcos-spartan
    * journalctl -fu dcos-exhibitor
    * journalctl -fu dcos-mesos-master (on masters)

A2: What installer did you use?  Try using the advanced installer.  It's a bit easier to use and a lot easier to troubleshoot and understand than the CLI and GUI installers.  A quick walkthrough of a very basic installation is available here: [Distributed DC/OS Cluster Setup](../distributed-setup.md)

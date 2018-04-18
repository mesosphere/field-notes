Before upgrading DC/OS or when you just want to have a ZooKeeper state backup every now and then you can follow these steps to create one.

All of these steps can be run on the DC/OS cluster you want to backup.

**1.)** First of all, download the Guano ZooKeeper backup tool by running:
wget https://github.com/adyatlov/guano/files/1321887/guano-0.1a.jar.zip

**2.)** Unzip the tool: 
`unzip guano-0.1a.jar.zip`

**3.)** Now run the following command to backup your current ZooKeeper state:

`/opt/mesosphere/bin/dcos-shell
java -jar guano-0.1a.jar -u super -p secret -d / -o /tmp/mesos-zk-backup -s $ZKHOST:2181 && tar -zcvf zkstate.tar.gz /tmp/mesos-zk-backup/`

**4.)** Be sure to copy the backup you just made over to a secure location.

TBD: Write Guano restore instructions...

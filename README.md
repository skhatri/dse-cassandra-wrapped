things stopping from running with readonly filesystem

tries to create

  mkdir -p /var/lib/spark/worker
  mkdir -p /var/lib/spark/rdd
  mkdir -p /var/log/spark/worker
  mkdir -p /var/log/spark/master

registers volumes:
                "/var/lib/cassandra": {},
                "/var/lib/dsefs": {},
                "/var/lib/spark": {},
                "/var/log/cassandra": {},
                "/var/log/spark": {}


to make it run in readonly file system

```
./build.sh
#mount additional folders for write
#DSE_AUTO_CONF_OFF=all to avoid rewriting data in cassandra/conf file
./run.sh
```

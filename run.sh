#!/usr/bin/env bash

. ./clean.sh

if [[ -d $(pwd)/volumes ]]; then rm -rf $(pwd)/volumes; fi;

mkdir -p $(pwd)/volumes/{lib-cassandra,lib-dsefs,lib-spark,log-cassandra,log-spark,conf-cassandra,tmp,.cassandra}

#-e DSE_AUTO_CONF_OFF=all

docker run \
--read-only \
--name dse \
-v $(pwd)/volumes/conf-cassandra:/opt/dse/resources/cassandra/conf \
-v $(pwd)/volumes/lib-cassandra:/var/lib/cassandra \
-v $(pwd)/volumes/lib-dsefs:/var/lib/dsefs \
-v $(pwd)/volumes/lib-spark:/var/lib/spark \
-v $(pwd)/volumes/log-cassandra:/var/log/cassandra \
-v $(pwd)/volumes/log-spark:/var/log/spark \
-v $(pwd)/volumes/tmp:/tmp \
-v $(pwd)/volumes/.cassandra:/opt/dse/.cassandra \
-p 9042:9042 \
-dt dse-server:latest

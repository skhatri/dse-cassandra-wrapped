#!/usr/bin/env bash

for x in $(docker ps -a --format '{{.ID}}:{{.Status}}'|grep -e "Exited\|Created"|awk -F":" '{print $1}');
do
  docker rm $x;
done;

for x in $(docker images -f dangling=true -q);
do
  docker rmi -f $x
done;


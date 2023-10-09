#!/bin/sh

for archive in /usr/dockerImages/*
do
  xz -d < $archive |
  podman load
done

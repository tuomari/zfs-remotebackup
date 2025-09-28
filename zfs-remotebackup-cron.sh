#!/bin/bash

pgrep -f zfs-remotebackup.sh || /usr/local/bin/zfs-remotebackup.sh /etc/zfs-remotebackup.conf

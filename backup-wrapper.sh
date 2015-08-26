#!/bin/bash
#
# Copyright(c) 2015 Iudex. All rights reserved
#

# Usage:
# ~/.ssh/authorized_keys
# command="BACKROOT='tank/remote-backup' /usr/local/bin/backup-wrapper.sh $SSH_ORIGINAL_COMMAND",from="127.0.0.1",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-rsa ...
#


if [ -z $BACKROOT ]; then
 echo "BACKROOT variable missing!";
fi

RCVCMD="mbuffer -q -v0 -s 128k -m 32M | /usr/bin/sudo /sbin/zfs receive $BACKROOT/$2"

case "$1" in
	list)
		sudo zfs list "$BACKROOT$2"
		;;
	receive)
		if [[ -z "$2" ]]
		  then
		  echo "dataset name required!";
		  exit 1;
		fi
		 eval $RCVCMD
		;;
	init)
	        vol=$BACKROOT;
		for i in `echo  $2 |sed 's|/[^/]*$||'|sed 's|/| |g'`; do
		   vol="$vol/$i";
		   /usr/bin/sudo /sbin/zfs create $vol;
                done;
		eval $RCVCMD;

		;;
        *)
		echo "Illegal command $1";
		;;
esac

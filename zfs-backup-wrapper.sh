#!/bin/bash
#
# Copyright(c) 2015 Iudex. All rights reserved
#

# Usage:
# ~/.ssh/authorized_keys
# command="BASEPATH='tank/remote-backup' /usr/local/bin/zfs-backup-wrapper.sh $SSH_ORIGINAL_COMMAND",from="127.0.0.1",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-rsa ...
#

COMMAND=$1;
ENDPATH=$2;

if [ -z "$BASEPATH" ]; then
 echo "BASEPATH variable missing!";
fi

if [ -z "$MBUFCMD" ]; then
  MBUFCMD="mbuffer -q -v0 -s 128k -m 32M"
fi

RCVCMD="$MBUFCMD | /usr/bin/sudo /sbin/zfs receive $BACKROOT/$ENDPATH"

case "$COMMAND" in
	list)
		sudo zfs list -r -t all "$BASEPATH/$ENDPATH";
		;;
	 snap)
                 sudo zfs snap "$BASEPATH/$ENDPATH"
                 ;;
	 receive)
		if [[ -z "$ENDPATH" ]]
		  then
		  echo "dataset name required!";
		  exit 1;
		fi
		 eval "$RCVCMD"
		;;
	init)
	        vol="$BASEPATH";
		for i in $(echo  "$ENDPATH" |sed 's|/[^/]*$||'|sed 's|/| |g'); do
		   vol="$vol/$i";
		   /usr/bin/sudo /sbin/zfs create "$vol";
                done;
		eval "$RCVCMD";

		;;
        *)
		echo "Illegal command $COMMAND";
		;;
esac

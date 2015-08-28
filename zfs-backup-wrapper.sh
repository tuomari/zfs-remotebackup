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

RCVCMD="$MBUFCMD | /usr/bin/sudo /sbin/zfs receive $BASEPATH/$ENDPATH"

function cleanup {

  echo "Running cleanup for $1 $2";
  if [[ -z $1 || -z $2 ]] ; then
     echo "TWO parameters required for cleanup: TARGET and SNAPTYPE"
     return 1;
  fi

 TARGET=$1;
 SNAPTYPE=$2
 SAVECOUNT=$(/sbin/zfs get -H -o value "$SNAP_SAVECOUNT_PROPERTY$SNAPTYPE" "$TARGET");

 # Default values for snapshots to save.
 if [[ -z $SAVECOUNT || ! $SAVECOUNT =~ ^[0-9]+$ ]]; then
   case "$SNAPTYPE" in
     "frequent") SAVECOUNT=48 ;;
     "daily") SAVECOUNT=31 ;;
     "weekly") SAVECOUNT=8 ;;
     "monthly") SAVECOUNT=12 ;;
   esac
 fi

# We always want to save atleast one snapshot of a kind.
#
if [ $SAVECOUNT -le 0 ]; then
 SAVECOUNT=1;
fi

 echo "Keeping latest $SAVECOUNT snapshots. destroying the rest from $TARGET with grep $SNAPNAME_PREFIX$SNAPTYPE$SNAPNAME_SUFFFIX";
 for i in $(sudo /sbin/zfs list -H -o name -r -t snapshot "$TARGET" |grep "$SNAPNAME_PREFIX$SNAPTYPE$SNAPNAME_SUFFFIX" |head -n -$SAVECOUNT); do 
   echo "Destroying $i";
   sudo /sbin/zfs destroy "$i";
 done

}

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
        cleanup)
		SNAPNAME_PREFIX="$5";
		SNAPNAME_SUFFFIX="$6";
		SNAP_SAVECOUNT_PROPERTY="$7";
		cleanup "$BASEPATH/$ENDPATH" "$3";
 		;;
       *)
		echo "Illegal command $COMMAND";
		;;
esac

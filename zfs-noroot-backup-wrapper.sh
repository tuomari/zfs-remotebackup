#!/bin/bash
#
# Copyright(c) 2015 Iudex. All rights reserved
#

# Usage:
# ~/.ssh/authorized_keys
# command="BASEPATH='tank/remote-backup' /usr/local/bin/zfs-backup-wrapper.sh $SSH_ORIGINAL_COMMAND",from="127.0.0.1",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-rsa ...



COMMAND=$1;
ENDPATH=$2;

if [ -z "$BASEPATH" ]; then
 echo "BASEPATH variable missing!";
fi

if [ -z "$MBUFCMD" ]; then
  MBUFCMD="pv -B 50M -q"
fi

RCVCMD="$MBUFCMD | /sbin/zfs receive $BASEPATH/$ENDPATH"

function cleanup {

 echo "Running cleanup for $1 $2";
  if [[ -z $1 || -z $2 ]] ; then
     echo "TWO parameters required for cleanup: TARGET and SNAPTYPE"
     return 1;
  fi

 TARGET="$BASEPATH/$1";
 SNAPTYPE="$2";
 SNAPNAME_PREFIX="$3";
 SNAP_SAVECOUNT_PROPERTY="$4";
 if [ ! -z "$SNAP_SAVECOUNT_PROPERTY" ]; then
    SAVECOUNT=$(/sbin/zfs get -H -o value "$SNAP_SAVECOUNT_PROPERTY$SNAPTYPE" "$TARGET");
 fi
 
# Default values for snapshots to save.
 if [[ -z $SAVECOUNT || ! $SAVECOUNT =~ ^[0-9]+$ ]]; then
   case "$SNAPTYPE" in
     "frequent") SAVECOUNT=48; ;;
     "daily") SAVECOUNT=31; ;;
     "weekly") SAVECOUNT=8; ;;
     "monthly") SAVECOUNT=12; ;;
     *) echo "Unknown savecount $SNAPTYPE"; exit 1; ;;
   esac
 fi
 echo "Savecount $SAVECOUNT for $SNAPTYPE";
# We always want to save atleast one snapshot of a kind.
#
if [ $SAVECOUNT -le 0 ]; then
 SAVECOUNT=1;
fi

 echo "Keeping latest $SAVECOUNT snapshots. destroying the rest from $TARGET with grep $SNAPNAME_PREFIX$SNAPTYPE$SNAPNAME_SUFFFIX";
 for i in $(/sbin/zfs list -H -o name -r -t snapshot "$TARGET" |grep "$SNAPNAME_PREFIX$SNAPTYPE$SNAPNAME_SUFFFIX" |head -n -$SAVECOUNT); do 
   echo "Destroying $i";
   sudo /sbin/zfs destroy "$i";
 done

}


function receive {
	if [[ -z "$ENDPATH" ]]
	  then
	  echo "dataset name required!";
	  exit 1;
	fi
	eval "$1";
}

function init {
   if [[ "$ENDPATH" == *"/"* ]]; then
	vol="$BASEPATH";
	for i in $(echo  "$ENDPATH" |sed 's|/[^/]*$||'|sed 's|/| |g'); do
	   vol="$vol/$i";
	   /sbin/zfs create "$vol";
	done;
   fi
   eval "$1";
}

case "$COMMAND" in
	list)
		sudo zfs list -r -t all "$BASEPATH/$ENDPATH";
		;;
	 snap)
                 sudo zfs snap "$BASEPATH/$ENDPATH"
                 ;;
	 zreceive)
	         receive "unpigz | $RCVCMD";
		;;
	 receive)
		receive "$RCVCMD";
		;;
	zinit)
	        init "unpigz | $RCVCMD";
		;;
	init)
		init "$RCVCMD";
		;;
	 snapshot)
	        SNAPNAME="$3";
	        /sbin/zfs snapshot "$BASEPATH/$ENDPATH@$SNAPNAME";
	        ;;
         cleanup)
		# $2 target, without $BASEPATH
		# $3 snaptype ( daily, weekly .. )
		# $4 snapshot name prefix
	 	# $5 snapshot savecount property, ie where we store how many daily,weekly snapshots should be saved
                cleanup "$2" "$3" "$4" "$5";
 		;;
       *)
		echo "Illegal command $COMMAND";
		;;
esac

#!/bin/bash
#
# Copyright(c) 2015 Iudex. All rights reserved
#

function initParams {

# Read env from file
if [[ ! -z $1 && -r $1 ]]; then
  . "$1";
fi

# Remote server credentials
if [[ -z $SSH_USERNAME || -z $SSH_HOSTNAME ]]; then
  echo "SSH_USERNAME and SSH_HOSTNAME are required!"
  exit 1
fi

# Snapshot name prefix and suffix
if [[ -z $SNAPNAME_PREFIX ]]; then
  SNAPNAME_PREFIX="iudex-backup-";
fi

if [[ -z $SNAPNAME_SUFFIX ]]; then
  SNAPNAME_SUFFIX=""
fi


# Zfs properties where backup data is stored
#
# What is the latest successfull snapshot sent to backup server
if [[ -z $SNAP_LATEST_PROPERTY ]]; then
  SNAP_LATEST_PROPERTY="iudex:backup-latest";
fi
# Destination name in remote server.
# Defaults to filesystem path without the pool name
# ie. for tank/hurr/durr -> hurr/durr
if [[ -z $SNAP_DST_PROPERTY ]]; then
  SNAP_DST_PROPERTY="iudex:backup-dst";
fi
# How many snapshts should we save 
# NOTICE: This property is suffixed with snapshot frequency
# ( frequent, daily, weekly or monthly )
if [[ -z $SNAP_SAVECOUNT_PROPERTY ]]; then
  SNAP_SAVECOUNT_PROPERTY="iudex:backup-savecount-"
fi

# Mbuffer options
# -q      | quiet
# -v0     | Verbose level 0
# -s128k  | Block size
# -m 256M | Total memory for buffer
# -R 5M	  | Rate limit buffer speed
# -W 300  | IO timeout.
if [[ -z $MBUF_OPTS ]]; then
  MBUF_OPTS="-q -v0 -s 128k -m 50M -R 5M -W 300";
fi

}

#############################################################
##################     STOP HERE    #########################
#############################################################

# For debug purposes only!
# If you want to force a snapshot date use: date -d "2015-06-23 11:33"
STARTTIME=$(date);

function send {
  if [[ -z $1 || -z $2 || -z $3 ]] ; then
    echo "THREE parameters required: INCREMENT_SNAPSHOT NEW_SNAPSHOT TARGET_NAME"
    return 1;
  fi

  if [[ $1 == "init" ]]; then
    echo "Initializing $2"
    /sbin/zfs send -e -v "$2" | mbuffer $MBUF_OPTS | ssh "$SSH_USERNAME@$SSH_HOSTNAME" "init $3"
  else
    echo "sending snapshot $1 -> $2 to $3 ";
    /sbin/zfs send -e -v -i "$1" "$2"  | mbuffer $MBUF_OPTS | ssh "$SSH_USERNAME@$SSH_HOSTNAME" "receive $3"
  fi
  ret=$?
  echo "ZFS send returnvalue $ret";
  # Return how zfs send command returned.
  return $ret;
}

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
 for i in $(/sbin/zfs list -H -o name -r -t snapshot "$TARGET" |grep "$SNAPNAME_PREFIX$SNAPTYPE$SNAPNAME_SUFFFIX" |head -n -$SAVECOUNT); do 
   echo "Destroying $i";
   /sbin/zfs destroy "$i";
 done

}

function backup {

if [[ -z $1 ]]; then
  echo "No backup target defined!!";
  return;
fi

TARGET=$1;
LATEST=$(/sbin/zfs get "$SNAP_LATEST_PROPERTY" "$TARGET" -H -o value);
DSTTARGET=$(/sbin/zfs get "$SNAP_DST_PROPERTY" "$TARGET" -H -o value);
echo "Backing up $TARGET. Latest backup $LATEST. Destination $DSTTARGET";

#Default snaptype t frequent
SNAPTYPE='frequent';

# Is this the first backup of the day?
if ! echo "$LATEST" | grep "$(date -d "$STARTTIME" +%Y-%m-%d)" ; then
  # First snapshot of the day. Make longer living snapshot.
  SNAPTYPE="daily";
  if [[ $(date -d "$STARTTIME" +%d) == "01" ]]; then
     # Today is first of month. Do monthly snapshot
     SNAPTYPE='monthly';
  elif [[ $(date -d "$STARTTIME" +%u) == "7" ]]; then
      # Today is sunday. Do weekly snapshot
      SNAPTYPE='weekly';
  fi
fi

SNAPNAME=$(date -d "$STARTTIME" +"$SNAPNAME_PREFIX$SNAPTYPE-%Y-%m-%d-%H%M%S$SNAPNAME_SUFFIX");

if( [[ -z $DSTTARGET  ]] || [[ $DSTTARGET == "-" ]] ); then
  DSTTARGET=$(echo "$TARGET" | sed 's|^[^/]*/||');
  /sbin/zfs set "$SNAP_DST_PROPERTY=$DSTTARGET" "$TARGET"
  echo "Warnin!! defaulting DSTTARGET $DSTTARGET";
fi

if( [[ -z $LATEST ]] || [[ $LATEST == "no" ]] ); then
   echo "Not backing up $TARGET";
   return;
fi

echo "DST: $DSTTARGET";

local NEWSNAP="$TARGET@$SNAPNAME";

/sbin/zfs snap "$NEWSNAP"

if [ "$?" -ne 0 ]; then
  echo "Creating snapshot $NEWSNAP failed..";
  return 1;
fi


if ( [[ $LATEST != "init" ]] ); then
  echo "Latest backed up snapshhot: $LATEST";
  SRCSNAP="$TARGET@$LATEST"
else
  echo "Initializing snapshot for $TARGET";
  SRCSNAP=$LATEST;
fi

send "$SRCSNAP" "$NEWSNAP" "$DSTTARGET";

if [ $? -ne 0 ]; then
  echo "Sending snapshot failed. Not updating latest backup..";
  return 1;
fi

/sbin/zfs set "$SNAP_LATEST_PROPERTY=$SNAPNAME" "$TARGET"
cleanup "$TARGET" "$SNAPTYPE";

}


case $1 in
     help)
	echo "$0 [backup|cleanup [frequent|daily|weekly|monthly]] [configfile]";
	exit 0;
     ;;
     backup)
       initParams "$2";
       CMD="backup";
     ;;

     cleanup)
        initParams "$3";
        SNAPTYPE="$2";
	CMD="cleanup";
    ;;

     *)
        initParams "$1";
	CMD="backup";
     ;;
esac;



for SOURCE in $(/sbin/zfs get "$SNAP_LATEST_PROPERTY" -r -t volume -H -o name,value|grep -v $'\t-'|cut -f 1 -d$'\t' ); do
   case "$CMD" in
     backup)
       backup "$SOURCE";
     ;;
     cleanup)
       cleanup "$SOURCE" "$SNAPTYPE";
     ;;
     *)
        echo "Unknown command $CMD";
        exit 1 ;   
     ;;
   esac
done



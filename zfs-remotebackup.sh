#!/bin/bash
#
# Copyright(c) 2015 Iudex. All rights reserved
#

function help {
   echo "$0 [backup|cleanup [frequent|daily|weekly|monthly]|cleanupfs [target] [frequent|daily|wekly|monthly]] [configfile]";
}

function initParams {


# Read env from file
if [[ ! -z $1 && -r $1 ]]; then
  . "$1";
fi


# Snapshot name prefix and suffix
if [[ -z $SNAPNAME_PREFIX ]]; then
  SNAPNAME_PREFIX="zfs-remote-backup-";
fi

if [[ -z $SEND_GZIP ]]; then
  SEND_GZIP="yes";
fi

if [[ -z $SNAPNAME_SUFFIX ]]; then
  SNAPNAME_SUFFIX=""
fi

if [[ -z $SSH_PORT ]]; then
  SSH_PORT="22";
fi

if [[ ! -z $ZFSBAK_HOSTNAME ]]; then

  # Zfs properties where backup data is stored
  #
  # What is the latest successfull snapshot sent to backup server
  if [[ -z $SNAP_LATEST_PROPERTY ]]; then
     SNAP_LATEST_PROPERTY="remotebackup-$ZFSBAK_HOSTNAME:backup-latest";
  fi

  # Destination name in remote server.
  # Defaults to filesystem path without the pool name
  # ie. for tank/hurr/durr -> hurr/durr
  if [[ -z $SNAP_DST_PROPERTY ]]; then
    SNAP_DST_PROPERTY="remotebackup-$ZFSBAK_HOSTNAME:backup-dst";
  fi
  # How many snapshts should we save 
  # NOTICE: This property is suffixed with snapshot frequency
  # ( frequent, daily, weekly or monthly )
  if [[ -z $SNAP_SAVECOUNT_PROPERTY ]]; then
    SNAP_SAVECOUNT_PROPERTY="remotebackup-$ZFSBAK_HOSTNAME:backup-savecount-"
  fi
fi

if [[ -z $SNAP_LATEST_PROPERTY ]]; then
   echo "SNAP_LATEST_PROPERTY not defined!"; 
   echo "Define either ZFSBAK_HOSTNAME or SNAP_LATEST_PROPERTY";
   exit 1;
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


# external scripts can be called after backup
# Three parameters are given
# - snapshot type (frequent|daily|weekly|monthly)
# - target name ie. tank/store/fs
# - snapshot name ie.: zfs-remotesend-2015-08-25_1234
#
# Allowed variable names:
# SCRIPT_FREQUENT_CMD
# SCRIPT_DAILY_CMD
# SCRIPT_WEEKLY_CMD
# SCRIPT_MONTHLY_CMD


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
    /sbin/zfs send -e -v "$2" | pigz | mbuffer $MBUF_OPTS | ssh -p "$SSH_PORT" "$SSH_USERNAME@$SSH_HOSTNAME" "zinit $3"
  else
    echo "sending snapshot $1 -> $2 to $3 ";
    /sbin/zfs send -e -v -i "$1" "$2" | pigz | mbuffer $MBUF_OPTS | ssh -p "$SSH_PORT" "$SSH_USERNAME@$SSH_HOSTNAME" "zreceive $3"
  fi
  ret=$?
  echo "Got state $ret from sending stuff to remote";
  if [ $ret -eq 0 ]; then
     /sbin/zfs set "$SNAP_LATEST_PROPERTY=$SNAPNAME" "$TARGET"
  fi


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
LATEST=$(/sbin/zfs get "$SNAP_LATEST_PROPERTY" "$TARGET" -H -o value -s local);
DSTTARGET=$(/sbin/zfs get "$SNAP_DST_PROPERTY" "$TARGET" -H -o value -s local);
echo "Backing up $TARGET. Latest backup $LATEST. Destination $DSTTARGET";

if [[ ! -z $FORCE_SNAPTYPE ]]; then
  SNAPTYPE="$FORCE_SNAPTYPE";
else
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

# Only send to remote when not doing frequent
if [ "$SNAPTYPE" != "frequent" ]; then
  send "$SRCSNAP" "$NEWSNAP" "$DSTTARGET";
  if [ $? -ne 0 ]; then
    echo "Sending snapshot failed...";
    return 1;
  fi
  # Remote cleanup
  ssh -p "$SSH_PORT" "$SSH_USERNAME@$SSH_HOSTNAME" "cleanup $DSTTARGET $SNAPTYPE $SNAPNAME_PREFIX $SNAP_SAVECOUNT_PROPERTY"  &

fi
# If backup callback function has been set, call it.
# Set variable name, and convert to uppercase
declare CALLBACK_CMD_NAME="SCRIPT_${SNAPTYPE^^}_CMD";
CALLBACK_CMD=${!CALLBACK_CMD_NAME};

if [ ! -z $CALLBACK_CMD ]; then
    # Call user defined callback script 
    nohup "$CALLBACK_CMD" "$SNAPTYPE" "$TARGET" "$SNAPNAME" &
fi

# Local cleanup
cleanup "$TARGET" "$SNAPTYPE";

}


function loopAll {

CMD="$1";

for SOURCE in $(/sbin/zfs get "$SNAP_LATEST_PROPERTY" -s local -r -t volume,filesystem -H -o name,value|egrep "(init|$SNAPNAME_PREFIX)" |grep -v $'\t-'|cut -f 1 -d$'\t' ); do
   case "$CMD" in
     backup)

       if [[ -z $SSH_USERNAME || -z $SSH_HOSTNAME || -z $SNAP_DST_PROPERTY || -z SNAP_SAVECOUNT_PROPERTY ]]; then
         echo "SSH_USERNAME, SSH_HOSTNAME, SNAP_DST_PROPERTY and SNAP_SAVECOUNT_PROPERTY are required!"
	 help;
	 exit 1
       fi
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

}

case $1 in
     help)
	help
	exit 0;
     ;;
     backup)
       initParams "$2";
       loopAll "backup";
     ;;

     cleanup)
        initParams "$3";
        SNAPTYPE="$2";
	loopAll "cleanup"
        ;;
     cleanupfs)
        initParams "$4";
        SNAPTYPE="$3";
	CLEANUPFS="$2";
	cleanup "$CLEANUPFS" "$SNAPTYPE";
        ;;
     *)
        initParams "$1";
	loopAll "backup"
     ;;
esac




echo "All done";

exit 0;

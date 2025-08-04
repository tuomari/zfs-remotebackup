#!/bin/bash
set -e

ZPATH="$1"

SNAPFILE=$(mktemp);

if [ -z "$ZPATH" ]; then
  exit 1;
fi

zfs list -r -o name -t snapshot "$ZPATH" > "$SNAPFILE"

if [ ! -f "$SNAPFILE" ]; then
 echo "No Snapfile found; $SNAPFILE"
 exit 1;
fi



echo "Remove failed daily snapshots, over a month old"
for i in $(cat "$SNAPFILE" |grep failed | grep  -- '-daily-'| grep -v -- "-daily-$(date +%Y-%m)-" |  grep -v -- "-daily-$(date +%Y-%m -d '-1 month')-" ); do
  echo "remove $i";
  zfs destroy "$i";
done

echo "Remove duplicat snapshots for same day"
for i in $(cat "$SNAPFILE" |grep failed|cut -f 1-6 -d '-'|uniq ); do
  echo Day $i; 
  for j in $(grep "$i" "$SNAPFILE"|grep failed |tail -n +2); do
    echo "remove $j";
    zfs destroy "$j";
  done;
done





rm "$SNAPFILE"

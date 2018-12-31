#!/bin/bash
#

trap "exit 1" TERM
export TOP_PID=$$


error_exit(){
  errmsg=$1
  logger -p ${SYSLOGFAC}.err -t $SYSLOGNAME "$errmsg"
  if [ -f $LOCKFILE ]; then
    rm -f $LOCKFILE
  fi
  if [ ! -z $debug ]; then echo "$err_msg"; fi
  kill -s TERM $TOP_PID
}

SYSLOGFAC="user"
SYSLOGNAME="libvirt_backup"
BACKUPDEST="$1"
DOMAIN="$2"
QUESTAGENT="$3"
MAXBACKUPS="$4"
debug="yes"

if [ -z "$BACKUPDEST" -o -z "$DOMAIN" ]; then
    error_exit  "Usage: ./vm-backup <backup-folder> <domain> [max-backups]"
fi

if [ -z "$MAXBACKUPS" ]; then
    MAXBACKUPS=6
else
  if [ "3" -gt "$MAXBACKUPS" ]; then
    MAXBACKUPS="3"
  fi
fi

if [ ! -z $debug ];then echo "Beginning backup for $DOMAIN"; fi

#
# Generate the backup path
#
BACKUPDATE=`date "+%Y-%m-%d.%H%M%S"`
BACKUPDOMAIN="$BACKUPDEST/$DOMAIN"
LOCKFILE=$BACKUPDOMAIN/lock

#Check for lock file, if one exists exit else create one
if [ -e $LOCKFILE ]; then
  logger -t $SYSLOGNAME -p ${SYSLOGFAC}.info "Backup for $DOMAIN not created. Lock file $LOCKFILE exists indicating another backup is in progress"
  exit 1
fi

touch $LOCKFILE
if [ $? != "0" ]; then
  error_exit "Could not write to directory  $BACKUPDOMAIN"
fi


BACKUP="$BACKUPDOMAIN/$BACKUPDATE"
if [ ! -z $debug ];then echo "BACKUP Directory = $BACKUP"; fi
mkdir -p "$BACKUP"

if [ $? != "0" ]; then
  error_exit "could not create directory $BACKUP"
fi

#
# Get the list of targets (disks) and the image paths.
#
TARGETS=`virsh domblklist "$DOMAIN" --details | grep ^file | grep -v 'cdrom' | grep -v 'floppy'| awk '{print $3}'`
IMAGES=`virsh domblklist "$DOMAIN" --details | grep ^file | grep -v 'cdrom' | grep -v 'floppy'| awk '{print $4}'`

if [ ! -z $debug ];then echo "TARGET  $TARGETS"; fi
if [ ! -z $debug ];then echo "IMAGES  $IMAGES"; fi
#
# Create the snapshot.
#
DISKSPEC=""
for t in $TARGETS; do
    DISKSPEC="$DISKSPEC --diskspec $t,snapshot=external"
done
options=''
if [ $QUESTAGENT == "yes" ]; then options='--quiesce'; fi
virsh snapshot-create-as --domain "$DOMAIN" --name backup $options --no-metadata \
	--atomic --disk-only $DISKSPEC >/dev/null
if [ $? -ne 0 ]; then
    error_exit "Failed to create snapshot for $DOMAIN"
fi

#
# Copy disk images
#
for t in $IMAGES; do
    NAME=`basename "$t"`
    cp "$t" "$BACKUP"/"$NAME"
done

#
# Merge changes back.
#
BACKUPIMAGES=`virsh domblklist "$DOMAIN" --details | grep ^file | grep -v 'cdrom' | grep -v 'floppy' |  awk '{print $4}'`
for t in $TARGETS; do
    virsh blockcommit "$DOMAIN" "$t" --active --pivot >/dev/null
    if [ $? -ne 0 ]; then
        error_exit "Could not merge changes for disk $t of $DOMAIN. VM may be in invalid state."
    fi
done

#
# Cleanup left over backup images.
#
for t in $BACKUPIMAGES; do
    rm -f "$t"
done

#
# Dump the configuration information.
#
virsh dumpxml "$DOMAIN" >"$BACKUP/$DOMAIN.xml"
if [ $? != 0 ]; then
  error_exit "Error during XML dump for $DOMAIN"
fi

#
# Cleanup older backups.
#
LIST=`ls -r1 "$BACKUPDOMAIN" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$'`
i=1
for b in $LIST; do
    if [ $i -gt "$MAXBACKUPS" ]; then
        backupname=`basename $b`
        logger -t 'libvirt_backup' -p user.info "Removing old backup $backupname"
        rm -rf "$BACKUPDOMAIN/$b"
    fi

    i=$[$i+1]
done

if [ -f $LOCKFILE ]; then
  rm -f $LOCKFILE
fi

exit 0

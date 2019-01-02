Overview
________
libvirt backups is a simple script that can be used to backup libvirt virtual
machines.   It requires qemu-ev and its active block commit capabilities.

Right now many of the settings are hardcoded, like the syslog facility, the minimum
number of backups, the location of the config file.

The Scripts
-----------
There are three pieces.  

libvirt_backup.sh
^^^^^^^^^^^^^^^^^
The parameters at this time are positional and it requires all 4.

1) The directory for the backup.  - no default  (The directory must exist at this point)
2) The domain  to be backed up.   - no default
3) Wether or not the agent is installed to quiesce the machine. default = no
4) Maximum number of backups to keep in the backup directory.   default = 6 (The value must be greater then 3)

The basic process is:
- Create the directory for the backup  under the backup directory:
    <domain name>/<date>
- Create an external snapshot.
- Copy the snapped disks to an alternate location.
- Copy the xml for the machine to  the alternate location.
- Remove the snapshot
- Check how many backups should be kept and remove oldest backup if number is exceeded.


Output is sent to syslog with the tag "libvirt_backup"

libvirt_backup_cron.rb
^^^^^^^^^^^^^^^^^^^^^^

Reads in the configuration file, /etc/libvirt_backup.conf  and calls libvirt_backup.sh for
each entry in the configuration file.  
It does some validation on the inputs.  It  will create the backup directory if it does not exist.  It chekcs to see if the domain name provided exists.

It logs information to the system log with the tag libvirt_backups_cron.



libvirt_backup.conf
^^^^^^^^^^^^^^^^^^^
Each line should contain a comma seperated list of the 4 parameters required for
libvirt_backup.sh. Lines begining with "#" are ignored.

An example:
# Backup Dir, Domain Name, Quiesce, Number of Backups to keep
/var/backups, my_vm,,
/var/altbackup,myothervm,yes,5






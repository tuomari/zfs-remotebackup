# zfs-remotebackup

Sudoers file:
 xxxhost-backupper ALL=(root) NOPASSWD: /sbin/zfs list tank/xxxhost-backup*,/sbin/zfs receive tank/xxxhost-backup/*, /sbin/zfs create tank/xxxhost-backup/*
or
 %zfs-backuppers ALL=(root) NOPASSWD: /sbin/zfs list tank/*-backup*,/sbin/zfs receive tank/*-backup/*, /sbin/zfs create tank/*-backup/*

# zfs-remotebackup

Sudoers file:
 xxxhost-backupper ALL=(root) NOPASSWD: /sbin/zfs list tank/xxxhost-backup*,/sbin/zfs receive tank/xxxhost-backup/*, /sbin/zfs create tank/xxxhost-backup/*
or
 %zfs-backuppers ALL=(root) NOPASSWD: /sbin/zfs list tank/*-backup*,/sbin/zfs receive tank/*-backup/*, /sbin/zfs create tank/*-backup/*


## to use nopass version add permissions to the target module:

```
zfs allow -u usernamegoeshere mount,create tank/k8-backup
zfs allow -du usernamegoeshere mount,create,receive,destroy tank/k8-backup
```

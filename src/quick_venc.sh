#!/bin/sh
# v507-production boot hook (run by vendor rcS)
touch /mnt/mtd/Log/9530Disable
mkdir -p /mnt/mtd/.ssh
cp -f /usr/share/ssh/authorized_keys /mnt/mtd/.ssh/authorized_keys
chmod 700 /mnt/mtd/.ssh
chmod 600 /mnt/mtd/.ssh/authorized_keys
# root home -> /mnt/mtd so dropbear finds ~/.ssh/authorized_keys
mount --bind /usr/share/ssh/passwd /etc/passwd
/usr/bin/dropbear -r /usr/share/ssh/dropbear_host_key -p 2222 -P /tmp/dropbear.pid -E >/dev/null 2>&1 &
exit 0

# linux

DDNSUPDATE

Scripts to update Microsoft DNS hosted zones by ISC-DHCPd. We share the servers keytab, this keytab will be updated
be sssd, so we do not worry about updating it. You have to put the server to the group "DnsUpdateProxy". The dhcpd 
process will drop its privileges, dues to this scripts called by this service can not access the system keytab. To
work around we use a cronjob to provide a valid credential-cache for the embedded nsupdate program.

1. ddnsupdate.sh - intended to be placed in /usr/local/sbin

2. ddnsupdate.cron -  intended to be placed in /etc/cron.d

3. ddnsupdate.include - intended to be placed in /etc/dhcpd.d

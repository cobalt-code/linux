# linux

1. DDNSUPDATE

Scripts to update Microsoft DNS hosted zones by ISC-DHCPd. 
We share the servers keytab, this keytab will be updated
be sssd, so we do need worry about updating it. You have 
to put the server to the group "DnsUpdateProxy" in the
ActiveDirectory. The dhcpd process will drop its privileges, 
due to this, scripts called by this service can not 
access the system keytab, which is owened by root only, 
we do not want to change this. To work around we use a 
cronjob to provide a valid credential-cache for the 
embedded nsupdate program in the ddnsupdate.sh script.

Files:

  ddnsupdate.sh - intended to be placed in /usr/local/sbin
  
  ddnsupdate.cron - intended to be placed in /etc/cron.d
  
  ddnsupdate.include - intended to be placed in /etc/dhcp

#!/bin/bash
#Run on CLEAN installs only
#WILL NOT FLUSH CURRENT IPTABLES RULES!
#####################################################
#Where your IPTables Command resides
IPT=/sbin/iptables
#The directory you want to use as your Temp Directory - /tmp is recommended
TEMPDIR=/tmp
#What tempfile you want to use
TEMPFILE=$TEMPDIR/viking.lk
#Where you want to permanently store your Viking data - /etc/viking is recommended for Debian/RHEL
PERMDIR=/etc/viking
#What you want to name your permanent ban file
PERMFILE=$PERMDIR/banlist
#What you want to name your whitelist
NOBANLIST=$PERMDIR/nobanlist
#Where you want your firewall data saved to
IPTSAVE=$PERMDIR/firewall.conf
#Where your allowed hosts file exists - debian is /etc/hsots.allow
HOSTSALLOW=/etc/hosts.allow
#Where you want to put your firewall restore script (using the init.d or network/if-up.d is recommended - debian)
IFUPDF=/etc/network/if-up.d/iptables
#Logfile
LOGFILE=/root/viking.log
#########################################################
mv viking.sh /usr/sbin/viking
mkdir $PERMDIR &&  echo "#!/bin/bash" > $IFUPDF && echo "iptables-restore < $IPTSAVE" >> $IFUPDF
mv firewall.conf > $IPTSAVE
crontab -l > cronadd
echo "* * * * * sh /usr/sbin/viking >> $LOGFILE" >> cronadd
crontab cronadd
rm cronadd
echo 0 > /proc/sys/net/ipv4/conf/all/accept_source_route
echo 1 > /proc/sys/net/ipv4/tcp_syncookies
echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects
echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter
echo 1 > /proc/sys/net/ipv4/conf/all/log_martians
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A FORWARD -o lo -j ACCEPT
iptables -A INPUT -p icmp --fragment -j LOG --log-level debug
iptables -A INPUT -p icmp --fragment -j DROP
iptables -A OUTPUT -p icmp --fragment -j LOG --log-level debug
iptables -A OUTPUT -p icmp --fragment -j DROP
iptables -A FORWARD -p icmp --fragment -j LOG --log-level debug
iptables -A FORWARD -p icmp --fragment -j DROP
iptables -A INPUT -p icmp -m limit --limit 1/s --limit-burst 2 -j ACCEPT
iptables -A INPUT -p icmp -m limit --limit 1/s --limit-burst 2 -j LOG --log-level debug
iptables -A INPUT -p icmp -j DROP
iptables -A OUTPUT -p icmp -j ACCEPT
iptables -A INPUT -m state --state NEW -p tcp --tcp-flags ALL ALL -j DROP
iptables -A INPUT -m state --state NEW -p tcp --tcp-flags ALL NONE -j DROP
iptables -N SYN_FLOOD
iptables -A INPUT -p tcp --syn -j SYN_FLOOD
iptables -A SYN_FLOOD -m limit --limit 5/s --limit-burst 10 -j RETURN
iptables -A SYN_FLOOD -j LOG --log-level debug
iptables -A SYN_FLOOD -j DROP
iptables-save > $IPTSAVE && exit 0
chmod +x $IFUPDF

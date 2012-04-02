#!/bin/bash
##Project Viking##
##Author: Sean Rice
##Work includes various snippets of code from around the internet
##Inquire to sean@rice-think.net for full sources
##This script is designed to be ran via root cron
#############################################################################
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
##############################################################################
#if Viking is already running, quit immediately
VIKRUN=$(ps -e | grep -co "viking")
if [ "$VIKRUN" -gt 0 ]
    then
        exit
    else
        :
fi
#If the $PERMFILE is not found, a first run is assumed and the hosts.deny file is parsed into the ban list, then firewall rules are added
if [ ! -f $PERMFILE ]
    then
        #If the $PERMFILE directory doesn't exist, create it then add the iptables restore file
        mkdir $PERMDIR &&  echo "#!/bin/bash" > $IFUPDF && echo "iptables-restore < $IPTSAVE" >> $IFUPDF
        touch $PERMFILE
        touch $NOBANLIST
        #Add several useful anti DoS prevention techniques
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
    else
        :
fi
#input a defined value (IE - an IP address) into the tempfile
if [ -n $1 ]
        then
                echo $1 |  tr -d '[:alpha:] [~`!@#$%^&*()_+=] [:blank:] [=-=]' >> $TEMPFILE
        else
                :
fi
#Collect information via netstat and write it to a temporary file if there are >50 concurrent connections from a single IP address
netstat -anp | grep 'tcp\|udp' | awk '{print $5 }' | cut -d: -f1 | sed '/^$/d' | sort | grep -v "0.0.0.0" | grep -v "127.0.0.1" | uniq -c | sort -n | sed '/^$/d' | sed -e 's/^[ \t]*//' | awk -F, '{ if ($0 > 50) print $0 }' | cut -d ' ' -f 2 >> $TEMPFILE
#Count the tempfile contents by line.  If it has less than 1 entry, exit the script
TFCOUNT=$(cat $TEMPFILE | wc -l)
if [ "$TFCOUNT" -lt 1 ]
    then
        exit
    else
        :
fi
# Create a new chain if it doesn't exist
DLEXIST=$(iptables --list -n | grep -o "Chain droplist")
if [ "$DLEXIST" = "Chain droplist" ]
    then
        :
    else
        $IPT -N droplist
fi
# Filter out comments and blank lines
# store each ip or subnet in $ip
egrep -v "^#|^$" $TEMPFILE | while IFS= read -r ip
do
    # Append only the new IPs to the droplist
    # Check the iptables rules currently in place for the IP
    TIP=$(iptables --list -n | grep -o $ip)
    # Check the hosts.allow file for the IP
    HAIP=$(cat $HOSTSALLOW | grep -o $ip)
    # Check the whitelist for the IP
    NBIP=$(cat $NOBANLIST | grep -o $ip)
    # If the SUM is <1, add the IP to the firewall ruleset
    if [ $TIP || $HAIP || $NBIP != $ip ]
        then
            $IPT -A droplist -s $ip -j DROP
            #Tell the program it needs to save the firewall ruleset
            date >> $LOGFILE
            echo "$ip" >> $LOGFILE
            NEEDSAVE="1"
        else
        :
    fi
done <"${TEMPFILE}"
# Write the new IP to the ban list
cat $TEMPFILE >> $PERMFILE
# Finally, insert or append our black list
if [ "$DLEXIST" = "Chain droplist" ]
    then
        :
    else
        $IPT -I INPUT -j droplist
        $IPT -I OUTPUT -j droplist
        $IPT -I FORWARD -j droplist
fi
# Remove the temp file
rm $TEMPFILE
# If there has been a new IP added to the firewall and ban list, save the firewall ruleset
if [ "$NEEDSAVE" = "1" ]
    then
        #Notify of new IP addresses added to the firewall, save the firewall, then exit
        echo "Added new IP addresses to the firewall" >> $LOGFILE
        iptables-save > $IPTSAVE && exit 0
    else
        exit 0
fi

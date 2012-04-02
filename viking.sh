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
if [ $TFCOUNT = 0 ]
    then
        exit 0
    else
        :
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

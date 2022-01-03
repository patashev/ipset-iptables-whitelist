#!/usr/bin/bash

# Wrote by Pavel Tashev
# NOTE!! Currently this script will lock all income to the
# official IPblock list for country that you've chose.
# For example for Bulgaria use 'bg' for USA use 'us'. The
# rules that are applyed are as follow: ACEPT listnening from
# country list of IPs. DROP all other.
# NOTE!! Deploying of rules is not limited to single chain. For 
# each file with pattern will be created additional chain. And will
# be applyed
#
# Chain whitelist (1 references)
# target     prot opt source               destination         
# RETURN     all  --  anywhere             anywhere             match-set zone-us-zone src
# DROP       all  --  anywhere             anywhere    
#
# Read flag of the command and decide
# if it is valid. If its valid, continue 
# to preparing folder structure.
name=false
while getopts h:c: flag
do
    case "${flag}" in
        c) name=${OPTARG};;
	h) "help menu :::TODO";;
	*) exit;;
    esac
done
if [[ "$name" == false ]];
then
	printf "use -c country\n"; exit 1;
else
	prepare_folder_sctructure $name
fi

# Starting to prepare the folder structure. First check
# if the folder excists and in the directory of script execution
# oif exsits continue without building structure. Else starting the
# dependacies and the security checks. And the continue to prepating
# to download the chain rules
function prepare_folder_sctructure()
{
	if ! [ -x "$(ls -a $PWD | grep zones)" ];
	then
		printf "There are no zones\n"
		dependencies
		mkdir $PWD/zones
		mkdir $PWD/zones/txt
		touch $PWD/zones/zone_scripts.sh && chmod a+x $PWD/zones/zone_scripts.sh
		prepare_download_zones $1
	else
		prepare_download_zones $1
	fi
}

# Function to check dependencies if no such, installing them.
# Executing the security checks.
function dependencies()
{
	declare -a resources=("ipset" "curl");
	for i in "${resources[@]}"
	do
		if [ $(dpkg-query -W -f='${Status}' $i 2>/dev/null | grep -c "ok installed") -eq 0 ];
		then
			echo "No $i."
			apt install $i -y
		fi
	done
	printf "All dipending packets are installed\n"
	security_check
}

# Check for other security mesures. If there such. Disable them
# Continue to building rc local service.
function security_check()
{
	firewall=$( ufw status )
	if [ "$firewall" == "Status: active" ];then ufw disable
   	fi
	rc_locale_service
}

# Building the RC Local service.
function rc_locale_service()
{
	touch /etc/systemd/system/rc-local.service
	touch /etc/rc.local
	echo "#!/usr/bin/bash" | tee -a /etc/rc.local
	cat <<EOF > /etc/systemd/system/rc-local.service
[Unit]
 Description=/etc/rc.local Compatibility
 ConditionPathExists=/etc/rc.local
[Service]
 Type=forking
 ExecStart=/etc/rc.local start
 TimeoutSec=0
 StandardOutput=tty
 RemainAfterExit=yes
[Install]
 WantedBy=multi-user.target
EOF
	chmod +x /etc/rc.local
	systemctl enable rc-local
	systemctl start rc-local
}

# Prepare Zone Chain rules for build the outpoint rules. For each line
# as a individual rule in the chain. Every rule is set in
# additional shell script called "zone_scripts". After setting
# the rulse deploy as IPtables ruls as follow: RIDIRECT from
# chain ALL on all ports. DROP all other traffic
# After all apply the the chain rc locale 
function prepare_zone_scripts_file()
{
	zone="zone-"$1
	line_one='$IPSET create '$zone" hash:net\n"
	line_two='$IPSET flush '$zone"\n"
	if [ $( du -hb $PWD/zones/zone_scripts.sh | grep -c 1) -eq 0 ];
	then
		cat <<EOF > $PWD/zones/zone_scripts.sh
#!/bin/sh
IPSET="/usr/sbin/ipset"
EOF

	echo '$IPSET' "create zone-$1-zone hash:net" | tee -a  $PWD/zones/zone_scripts.sh
	echo '$IPSET' "flush zone-$1-zone" | tee -a $PWD/zones/zone_scripts.sh
	fi
	for f in $PWD/zones/txt/*-zone;
        do
		while read -r line; do $( echo '$IPSET' "add zone-$1-zone $line" | tee -a  $PWD/zones/zone_scripts.sh ); done < $f 2>/dev/null
        done
	tail -n +2 zones/zone_scripts.sh | tee -a /etc/rc.local
	$( sh $PWD/zones/zone_scripts.sh )
	iptables -N whitelist
	iptables -A INPUT -i eth0 -p tcp -m state --state NEW -j whitelist
	iptables -A whitelist -m set --match-set zone-$1-zone src -j RETURN
	iptables -A whitelist -j DROP

	#### za posle za :::TODO
	##mkdir /etc/iptables 2>/dev/null
	##$( su -c 'iptables-save > /etc/iptables/rules.v4' )
}

# Here we prepare the rules for download. 
# ***************************************
# Currently that script is reading the official IPblock database
# The idea is to connect to extplorer with curl on webdav. 
# This way we can automate and secure the rule lists
function prepare_download_zones()
{
	if [ $( du -hb $PWD/zones/txt | col1 ) -eq 2 ];
	then
		printf "The folder txt is empty\n"
		curl -s 'https://www.ipdeny.com/ipblocks/' | \
			sed -n 's/.*href="\([^"]*\).*/\1/p' | \
			awk '$0="https://www.ipdeny.com/ipblocks/"$0' | \
			head -n -5 | \
			sed -e '1,11d' | \
			grep "$1" > $PWD/zones/download

		while IFS="" read -r p || [ -n "$p" ]
		do
  			wget "$p" -P $PWD/zones/txt/ 
		done < $PWD/zones/download
		for f in $PWD/zones/txt/*.zone;
            do
                mv "$f" "$(echo "$f" | sed 's/aggregated.//g' )" 2>/dev/null;
            done
		prepare_zone_scripts_file $1
	else
		for f in $PWD/zones/txt/*.zone; 
		do 
			mv "$f" "$(echo "$f" | sed 's/aggregated.//g' )" 2>/dev/null;
	       	done
		prepare_zone_scripts_file $1
	fi
}



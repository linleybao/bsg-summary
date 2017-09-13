#!/bin/bash
##version 0.0.8 
##date 2016年 8月 3日 星期三 13时44分17秒 CST

check_details (){
	local s_file=/tmp/check.tmp
	local d_file=$1
	local out=`diff -b ${s_file} ${d_file} | wc -l`
	if [ ${out} -eq 0  ]; then
		mid_v="OK"
	else
		mid_v="Warning"
	fi
}

csv_format (){
	local cell="$1"
	echo -n "\"${cell}\"," >> ${output_file}
}

csv_format_end (){
	local cell="$1"
	echo "\"${cell}\"" >> ${output_file}
}

create_head (){
	csv_format "Hostname"
	csv_format "System time"
	csv_format "IP address"
	csv_format "Gateway"
	csv_format "Uptime"
	csv_format "System"
	csv_format "Kernel"
	csv_format "Architecture"
	csv_format "Virtualized"
	csv_format "Processors"
	csv_format "Mem Total"
	csv_format "Mem Free"
	csv_format "Mem Used"
	csv_format "Mounted Filesystems"
	csv_format "RAID Level"
	csv_format "Multipath Status"
	csv_format "Eth Link Status"
	csv_format "Bond Status"
	csv_format "Network Connections"
	csv_format "Services Status"
	csv_format "Services Settings"
	csv_format "Security Police"
	csv_format "Root Crontab"
	csv_format_end "RHCS status"

}

insert_data (){
	system_time=`grep -E "*Date\ \|" ${input_file} | awk -F "|" '{print $2}' | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	hostname=`grep -E "Hostname\ \|" ${input_file} | awk -F "|" '{print $2}' | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	ip_address=`grep -E "IP\ address\ \|" ${input_file} | awk -F "|" '{print $2}' | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	gateway=`grep -E "GATEWAY" ${input_file} | head -1 | awk -F "=" '{print $2}' | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	uptime=`grep -E "Uptime\ \|" ${input_file} | awk -F "|" '{print $2}' | awk -F , '{print $1}' | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	system=`grep -E "System\ \|" ${input_file} | awk -F "|" '{print $2}'  | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	kernel=`grep -E "Kernel\ \|" ${input_file} | awk -F "|" '{print $2}'  | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	arch=`grep -E "Architecture\ \|" ${input_file} | awk -F "|" '{print $2}' | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	virtualized=`grep -E "Virtualized\ \|" ${input_file} | awk -F "|" '{print $2}'  | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	processors=`grep -E "Processors\ \|" ${input_file} | awk -F "|" '{print $2}'  | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	memtotal=`grep -E "Total\ \|" ${input_file} | awk -F "|" '{print $2}'  | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	memfree=`grep -E "Free\ \|" ${input_file} | awk -F "|" '{print $2}'  | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	memused=`grep -E "Used\ \|" ${input_file} | awk -F "|" '{print $2}' | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	mountfs=`awk 'BEGIN{RS="# ";ORS="# "} /Mounted\ Filesystems/' ${input_file}  | grep -vE "Mounted|^#" | awk '{print $6 "    ," $3}' | grep -v "Mountpoint" | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	raid_level=`awk 'BEGIN{RS="# ";ORS="# "} /RAID\ Controller/' ${input_file}  | grep "logicaldrive" | awk -F, '{print $2}' | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	multipath_status=`awk 'BEGIN{RS="# ";ORS="# "} /Multipath\ Status/' ${input_file}| grep -vE "Multipath Status|^#" | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	eth_link_status=`awk 'BEGIN{RS="# ";ORS="# "} /Network Config/' ${input_file} | grep "Link detected:"`
	bond_status=`egrep -A 5 "^- bond[0-9] status" ${input_file} | egrep -v "^Ethernet Channel|^$|^--"`
	net_conn=`awk 'BEGIN{RS="# ";ORS="# "} /Network\ Connections/' ${input_file} | grep -vE "Network|^#" | grep -E "ESTABLISHED|LISTEN" | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	service_status=`awk 'BEGIN{RS="# ";ORS="# "} /Services\ status/' ${input_file} | grep -vE "Services|^  $|^#|OK" | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	awk 'BEGIN{RS="# ";ORS="# "} /Services\ settings/' ${input_file} | grep -vE "Services settings|^#" | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g' > /tmp/check.tmp
	check_details /tmp/settings.std 
	service_settings=${mid_v}
	awk 'BEGIN{RS="# ";ORS="# "} /Security\ Police/' ${input_file} | grep -vE "Security Police|^#" | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g' > /tmp/check.tmp
	check_details /tmp/security.std 
	s_status=${mid_v}
	root_cron=`awk 'BEGIN{RS="# ";ORS="# "} /Root\ crontab/' ${input_file} | grep -vE "Root crontab|^#" | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`
	rhcs_status=`sed -n '/Member Name/,/- RHCS config/p' ${input_file} | grep -vE "RHCS config|^$" | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'`

	csv_format "$hostname"
	csv_format "$system_time"
	csv_format "$ip_address"
	csv_format "$gateway"
	csv_format "$uptime"
	csv_format "$system"
	csv_format "$kernel"
	csv_format "$arch"
	csv_format "$virtualized"
	csv_format "$processors"
	csv_format "$memtotal"
	csv_format "$memfree"
	csv_format "$memused"
	csv_format "$mountfs"
	csv_format "$raid_level"
	csv_format "$multipath_status"
	csv_format "$eth_link_status"
	csv_format "$bond_status"
	csv_format "$net_conn"
	csv_format "$service_status"
	csv_format "$service_settings"
	csv_format "$s_status"
	csv_format "$root_cron"
	csv_format_end "$rhcs_status"
}

date=`date +%Y-%m`
output_file="bank_of_shanghai_${date}.csv"

#make secuity standard
echo "PASS_MAX_DAYS   90
PASS_MIN_DAYS   0
PASS_MIN_LEN    8
PASS_WARN_AGE   60

auth        required      pam_tally.so onerr=fail deny=6
auth        sufficient    pam_unix.so nullok try_first_pass
account     required      pam_unix.so
password    requisite     pam_cracklib.so try_first_pass retry=3 minlen=8 lcredit=-1 ucredit=-1 dcredit=-1 ocredit=-1
password    sufficient    pam_unix.so md5 remember=3 shadow nullok try_first_pass use_authtok
session     required      pam_unix.so

umask 027
umask 027
TMOUT=300" > /tmp/security.std

#make service settings standard
echo "- snmpd ---------------------------------------
OPTIONS=\"-Lf /var/log/snmpd.log\"
- sshd ----------------------------------------
PermitRootLogin no
- logrotate -----------------------------------
rotate 25
compress" > /tmp/settings.std

create_head

for file in `ls | egrep "*.txt"`; do
	input_file=${file}
	insert_data
done


rm -f /tmp/check.tmp
rm -f /tmp/security.std
rm -f /tmp/settings.std

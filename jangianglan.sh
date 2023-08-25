#!/bin/sh
random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c5
	echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}
install_3proxy() {
    echo "installing 3proxy"
    URL="https://raw.githubusercontent.com/Jangiang/proxytao/blob/main/3proxy-3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
#auth strong

#users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "#auth strong\n" \
"#allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"

}
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig enp0s3 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}
echo "installing apps"
yum -y install gcc net-tools bsdtar zip >/dev/null

install_3proxy

echo "working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

# Get the default network interface (usually eth0 or enp0s3)
default_interface=$(ip route | awk '/default/ {print $5}')

# Get the internal IPv4 address of the default network interface
IP4=$(ip addr show dev $default_interface | awk '/inet / {print $2}' | grep -oE '([0-9]+\.){3}[0-9]+')

# Assign the internal IPv4 address to a variable (optional)
internal_ip_variable=$IP4

IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IPv4 = ${IP4}. Exteranl sub for IPv6 = ${IP6}"

echo "How many proxy do you want to create? Example 500"
COUNT=300  # Set the number of proxies you want
echo "$COUNT"
#read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

bash /etc/rc.local


# Read the new DNS server IP address from user input
new_dns_server="8.8.8.8"  # Set the DNS server IP address
echo "$new_dns_server"
read -p "Enter the DNS server IP address: " new_dns_server

# Escape the dots in the IP address for sed
escaped_dns_server=$(echo "$new_dns_server" | sed 's/\./\\./g')

# Set the path to the 3proxy.cfg file
config_file="/root/3proxy-3proxy-0.8.6/scripts/3proxy.cfg"

# Check if the file exists
if [ -f "$config_file" ]; then
    # Use sed to replace the old IP address with the new one
    sed -i "s/nserver 127\.0\.0\.1/nserver $escaped_dns_server/" "$config_file"
    echo "DNS server IP address updated to: $new_dns_server"
else
    echo "Error: Configuration file not found."
fi   # Add this 'fi' to close the if block

gen_proxy_file_for_user

upload_proxy

#!/bin/bash
# filepath: /etc/openvpn/setup_openvpn.sh

# Update system
apt-get update
apt-get upgrade -y

# Install OpenVPN and easy-rsa
apt-get install -y openvpn easy-rsa

# Copy easy-rsa files to OpenVPN directory
make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa

# Initialize PKI
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa gen-dh
openvpn --genkey secret ta.key

# Generate server certificate
./easyrsa build-server-full server nopass

# Create OpenVPN server configuration
cat > /etc/openvpn/server.conf << EOF
port 1194
proto udp
dev tun
ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/server.crt
key /etc/openvpn/easy-rsa/pki/private/server.key
dh /etc/openvpn/easy-rsa/pki/dh.pem
server 10.8.0.0 255.255.255.0
ifconfig 192.168.2.236 255.255.255.0
push "redirect-gateway def1"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
tls-auth /etc/openvpn/easy-rsa/ta.key 0
cipher AES-256-CBC
auth SHA256
comp-lzo
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
log-append /var/log/openvpn/openvpn.log
verb 3
EOF

# Create log directory
mkdir -p /var/log/openvpn

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# Configure firewall rules
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

# Enable and start OpenVPN service
systemctl enable openvpn@server
systemctl start openvpn@server

echo "OpenVPN server configuration completed!"

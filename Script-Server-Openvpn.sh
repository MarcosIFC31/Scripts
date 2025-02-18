#!/bin/bash

# OpenVPN Auto-Configuration Script

# Variables
OPENVPN_DIR="/etc/openvpn"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"
CLIENT_NAME="client"

# Update and install OpenVPN and Easy-RSA
echo "Updating package list and installing OpenVPN and Easy-RSA..."
apt-get update
apt-get install -y openvpn easy-rsa

# Set up the Easy-RSA directory
echo "Setting up Easy-RSA directory..."
make-cadir $EASY_RSA_DIR
cd $EASY_RSA_DIR

# Initialize and build the CA
echo "Initializing and building the CA..."
./easyrsa init-pki
./easyrsa build-ca nopass

# Generate server certificate and key
echo "Generating server certificate and key..."
./easyrsa gen-req server nopass
./easyrsa sign-req server server

# Generate Diffie-Hellman parameters
echo "Generating Diffie-Hellman parameters..."
./easyrsa gen-dh

# Generate HMAC signature
echo "Generating HMAC signature..."
openvpn --genkey --secret ta.key

# Move certificates and keys to OpenVPN directory
echo "Moving certificates and keys to OpenVPN directory..."
cp pki/ca.crt $OPENVPN_DIR/
cp pki/issued/server.crt $OPENVPN_DIR/
cp pki/private/server.key $OPENVPN_DIR/
cp pki/dh.pem $OPENVPN_DIR/
cp ta.key $OPENVPN_DIR/

# Configure OpenVPN server
echo "Configuring OpenVPN server..."
cat > $OPENVPN_DIR/server.conf <<EOF
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
tls-auth ta.key 0
cipher AES-256-CBC
persist-key
persist-tun
status openvpn-status.log
verb 3
EOF

# Enable IP forwarding
echo "Enabling IP forwarding..."
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# Configure iptables for NAT
echo "Configuring iptables for NAT..."
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

# Enable and start OpenVPN service
echo "Enabling and starting OpenVPN service..."
systemctl enable openvpn@server
systemctl start openvpn@server

# Generate client configuration
echo "Generating client configuration..."
mkdir -p $OPENVPN_DIR/client-configs
cd $OPENVPN_DIR/client-configs
cp $EASY_RSA_DIR/ta.key .
cp $EASY_RSA_DIR/pki/ca.crt .
cp $EASY_RSA_DIR/pki/private/$CLIENT_NAME.key .
cp $EASY_RSA_DIR/pki/issued/$CLIENT_NAME.crt .

cat > $CLIENT_NAME.ovpn <<EOF
client
dev tun
proto udp
remote YOUR_SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert $CLIENT_NAME.crt
key $CLIENT_NAME.key
remote-cert-tls server
tls-auth ta.key 1
cipher AES-256-CBC
verb 3
EOF

echo "OpenVPN server setup complete!"
echo "Client configuration file is located at $OPENVPN_DIR/client-configs/$CLIENT_NAME.ovpn"
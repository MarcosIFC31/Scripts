#!/bin/bash

# OpenVPN Auto-Configuration Script
# Configuración para IP 192.168.60.135

# Variables
OPENVPN_DIR="/etc/openvpn"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"
CLIENT_NAME="client"
SERVER_IP="192.168.60.135"  # IP del servidor OpenVPN

# Verificar si el usuario es root
if [ "$EUID" -ne 0 ]; then
  echo "Este script debe ejecutarse como root. Usa 'sudo' para ejecutarlo."
  exit 1
fi

# Actualizar e instalar OpenVPN y Easy-RSA
echo "Actualizando la lista de paquetes e instalando OpenVPN y Easy-RSA..."
apt-get update
apt-get install -y openvpn easy-rsa

# Configurar el directorio de Easy-RSA
echo "Configurando el directorio de Easy-RSA..."
make-cadir $EASY_RSA_DIR
cd $EASY_RSA_DIR

# Inicializar y construir la CA
echo "Inicializando y construyendo la CA..."
./easyrsa init-pki
./easyrsa build-ca nopass

# Generar el certificado y la clave del servidor
echo "Generando el certificado y la clave del servidor..."
./easyrsa gen-req server nopass
./easyrsa sign-req server server

# Generar parámetros Diffie-Hellman
echo "Generando parámetros Diffie-Hellman..."
./easyrsa gen-dh

# Generar firma HMAC
echo "Generando firma HMAC..."
openvpn --genkey --secret ta.key

# Mover certificados y claves al directorio de OpenVPN
echo "Moviendo certificados y claves al directorio de OpenVPN..."
cp pki/ca.crt $OPENVPN_DIR/
cp pki/issued/server.crt $OPENVPN_DIR/
cp pki/private/server.key $OPENVPN_DIR/
cp pki/dh.pem $OPENVPN_DIR/
cp ta.key $OPENVPN_DIR/

# Configurar el servidor OpenVPN
echo "Configurando el servidor OpenVPN..."
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

# Habilitar el reenvío de IP
echo "Habilitando el reenvío de IP..."
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# Configurar iptables para NAT
echo "Configurando iptables para NAT..."
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

# Habilitar e iniciar el servicio de OpenVPN
echo "Habilitando e iniciando el servicio de OpenVPN..."
systemctl enable openvpn@server
systemctl start openvpn@server

# Generar configuración del cliente
echo "Generando configuración del cliente..."
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
remote $SERVER_IP 1194
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

echo "¡Configuración del servidor OpenVPN completada!"
echo "El archivo de configuración del cliente está en: $OPENVPN_DIR/client-configs/$CLIENT_NAME.ovpn"
echo "Transfiere este archivo a tu dispositivo cliente para conectarte al VPN."

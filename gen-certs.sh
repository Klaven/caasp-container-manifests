#!/bin/bash

set -e

CACN=${CACN:-CaaSP Internal CA}
ORG=${ORG:-SUSE Internal}
ORGUNIT=${ORGUNIT:-CaaSP}
CITY=${CITY:-Nuremberg}
STATE=${STATE:-Bavaria}
COUNTRY=${COUNTRY:-DE}

dir() {
    echo "/etc/pki"
}

certs() {
    echo "$(dir)/_certs"
}

privatedir() {
    echo "/etc/pki/private"
}

work() {
    echo "$(dir)/_work"
}

genca() {
    [ -f $(privatedir)/ca.key ] && [ -f $(dir)/ca.crt ] && return

    echo "Generating CA Certificate"

    mkdir -p $(work)
    mkdir -p $(certs)
    mkdir -p -m 700 $(privatedir)

    # generate the CA _work key
    (umask 377 && openssl genrsa -out $(privatedir)/ca.key 4096)

    cat > $(work)/ca.cfg <<EOF
[ca]
default_ca = CA_default

[CA_default]
dir = $(dir)
certs	= \$dir
database = $(work)/index.txt
new_certs_dir	= $(certs)

certificate	= \$dir/ca.crt
serial = $(work)/serial
private_key	= $(privatedir)/ca.key
RANDFILE = \$dir/.rand

default_days = 365
default_md = default
preserve = false
copy_extensions = copy

policy          = policy_match

[ policy_match ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $ORGUNIT
CN = $CACN

[v3_ca]
# Extensions to add to a CA certificate request
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
basicConstraints = critical, CA:TRUE
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment, keyCertSign

[v3_req]
# Extensions to add to a server certificate request
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
EOF

    rm -f $(work)/index.txt $(work)/index.txt.attr
    touch $(work)/index.txt $(work)/index.txt.attr
    echo 1000 > $(work)/serial

    openssl req -batch -config $(work)/ca.cfg -sha256 -new -x509 -days 3650 -extensions v3_ca -key $(privatedir)/ca.key -out $(dir)/ca.crt
}

gencert() {
    [ -f $(privatedir)/$1.key ] && [ -f $(dir)/$1.crt ] && return

    echo "Generating $1 Certificate"

    # generate the server cert
    (umask 377 && openssl genrsa -out $(privatedir)/$1.key 2048)

    cat > $(work)/$1.cfg <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $ORGUNIT
CN = $2

[v3_req]
# Extensions to add to a certificate request
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
EOF

    count=0
    for dnsalt in $3
    do
        count=$((count + 1))
        echo "DNS.${count} = ${dnsalt}" >> $(work)/$1.cfg
    done

    count=0
    for ipalt in $4
    do
        count=$((count + 1))
        echo "IP.${count} = ${ipalt}" >> $(work)/$1.cfg
    done

    # generate the server csr
    openssl req -batch -config $(work)/$1.cfg -new -sha256 -nodes -extensions v3_req -key $(privatedir)/$1.key -out $(work)/$1.csr

    # sign the server cert
    openssl ca -batch -config $(work)/ca.cfg -extensions v3_req -notext -in $(work)/$1.csr -out $(dir)/$1.crt

    # final verification
    openssl verify -CAfile $(dir)/ca.crt $(dir)/$1.crt
}

ip_addresses() {
    ifconfig | grep -Po 'inet addr:\K[\d.]+' | grep -v '127.0.0.1' | tr '\n' ' '
}

all_hostnames=$(echo "$(hostname) $(hostname --fqdn) $(hostnamectl --transient) $(hostnamectl --static) \
                      $(cat /etc/hostname)" | tr ' ' '\n' | sort -u | tr '\n' ' ')

genca
gencert "velum" "$(hostname)" "$all_hostnames" "$(ip_addresses)"
gencert "salt-api" "salt-api.infra.caasp.local" "" "127.0.0.1"

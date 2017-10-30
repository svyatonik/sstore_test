#!/bin/bash
function join_by { local IFS="$1"; shift; echo "$*"; }

NUM_NODES=100
NETWORK_PORT_BASE=1000
SSTORE_INTERNAL_PORT_BASE=2000
SSTORE_HTTP_PORT_BASE=3000

rm -rf db.*
rm -rf *.toml
for i in `seq 1 $NUM_NODES`
do
	openssl ecparam -name secp256k1 -genkey -noout | openssl ec -text -noout > key 2>/dev/null
	network_port[i]=$(($NETWORK_PORT_BASE+$i))
	sstore_internal_port[i]=$(($SSTORE_INTERNAL_PORT_BASE+$i))
	sstore_http_port[i]=$(($SSTORE_HTTP_PORT_BASE+$i))
	if [ "$i" -eq 1 ]; then
		sstore_http_port[i]=8082
	fi
	secret[i]=`cat key | grep priv -A 3 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^00//'|xargs -0 printf "%64s"|tr ' ' '0'`
	public[i]=`cat key | grep pub -A 5 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^04//'|xargs -0 printf "%64s"|tr ' ' '0'`
	enode[i]="\"enode://${public[i]}@127.0.0.1:${network_port[i]}\""
	ssnode[i]="\"${public[i]}@127.0.0.1:${sstore_internal_port[i]}\""
done
rm key

for i in `seq 1 $NUM_NODES`
do
	self_enode=${enode[i]}
	bootnodes=("${enode[@]/$self_enode}")
	bootnodes=$(join_by , ${bootnodes[@]})
	self_ssnode=${ssnode[i]}
	ssnodes=("${ssnode[@]/$self_ssnode}")
	ssnodes=$(join_by , ${ssnodes[@]})
	disable_ui="true"
	if [ "$i" -eq 1 ]; then
		disable_ui="false"
	fi
	config_contents="
# node#$i
# self_secret: ${secret[i]}
# self_public: ${public[i]}

[parity]
chain = \"dev\"
base_path = \"db.dev_ss${i}\"

[ui]
disable = $disable_ui

[rpc]
disable = $disable_ui

[websockets]
disable = $disable_ui

[ipc]
disable = $disable_ui

[dapps]
disable = $disable_ui

[network]
port = ${network_port[i]}
node_key = \"${secret[i]}\"
bootnodes = [$bootnodes]

[ipfs]
enable = false

[snapshots]
disable_periodic = true

[secretstore]
disable = false
disable_acl_check = true
self_secret = \"${secret[i]}\"
nodes = [$ssnodes]
interface = \"local\"
port = ${sstore_internal_port[i]}
http_interface = \"local\"
http_port = ${sstore_http_port[i]}
path = \"db.dev_ss${i}/secretstore\"
"
	echo "$config_contents" >"dev_ss${i}.toml"
done

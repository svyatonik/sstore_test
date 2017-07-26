#!/bin/bash
function join_by { local IFS="$1"; shift; echo "$*"; }

NUM_NODES=360
THRESHOLD=240
NETWORK_PORT_BASE=30000
SSTORE_INTERNAL_PORT_BASE=40000
SSTORE_HTTP_PORT_BASE=50000

for i in `seq 1 $NUM_NODES`
do
	openssl ecparam -name secp256k1 -genkey -noout | openssl ec -text -noout > key 2>/dev/null
	network_port[i]=$(($NETWORK_PORT_BASE+$i))
	sstore_internal_port[i]=$(($SSTORE_INTERNAL_PORT_BASE+$i))
	sstore_http_port[i]=$(($SSTORE_HTTP_PORT_BASE+$i))
	secret[i]=`cat key | grep priv -A 3 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^00//'`
	public[i]=`cat key | grep pub -A 5 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^04//'`
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
	config_contents="[parity]
chain = \"dev\"
base_path = \"db.dev_ss${i}\"

[ui]
disable = false

[rpc]
disable = false

[ipc]
disable = true

[websockets]
disable = false

[dapps]
disable = false

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

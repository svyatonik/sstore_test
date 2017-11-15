#!/bin/bash

# Deploys PoA network with next parameters:
# 1) NUM_AUTHORITIES authorities nodes
# 2) NUM_REGULAR regular nodes
# 3) every authority node is running a key server = single SS

function join_by { local IFS="$1"; shift; echo "$*"; }

NUM_AUTHORITIES=10
NUM_REGULAR=1
NUM_NODES=$(($NUM_AUTHORITIES+$NUM_REGULAR))
UI_PORT_BASE=8180
RPC_PORT_BASE=8545
WS_PORT_BASE=8600
NETWORK_PORT_BASE=10000
SSTORE_INTERNAL_PORT_BASE=12000
SSTORE_HTTP_PORT_BASE=13000

###############################################################################
### generate keys #############################################################
###############################################################################
rm -rf db.*
rm -rf *.toml
for i in `seq 1 $NUM_NODES`
do
	openssl ecparam -name secp256k1 -genkey -noout | openssl ec -text -noout > key 2>/dev/null
	ui_port[i]=$(($UI_PORT_BASE+$i-1))
	rpc_port[i]=$(($RPC_PORT_BASE+$i-1))
	ws_port[i]=$(($WS_PORT_BASE+$i-1))
	network_port[i]=$(($NETWORK_PORT_BASE+$i-1))
	secret[i]=`cat key | grep priv -A 3 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^00//'|xargs -0 printf "%64s"|tr ' ' '0'`
	public[i]=`cat key | grep pub -A 5 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^04//'|xargs -0 printf "%64s"|tr ' ' '0'`
	enode[i]="\"enode://${public[i]}@127.0.0.1:${network_port[i]}\""
	if [ "$i" -le "$NUM_AUTHORITIES" ]; then
		sstore_internal_port[i]=$(($SSTORE_INTERNAL_PORT_BASE+$i-1))
		sstore_http_port[i]=$(($SSTORE_HTTP_PORT_BASE+$i-1))
		if [ "$i" -eq 1 ]; then
			sstore_http_port[i]=8082
		fi
		ssnode[i]="\"${public[i]}@127.0.0.1:${sstore_internal_port[i]}\""
	fi
done
rm key

###############################################################################
### insert accounts && password file ##########################################
###############################################################################
json_validators_list=""
json_acccounts_list=""
echo password>password_file
for i in `seq 1 $NUM_NODES`
do
	address=`../ethstore insert ${secret[i]} password_file --dir db.poa_ss${i}/keys/POA`
	addresses[i]=$address
	comma=","
	if [ "$i" -eq 1 ]; then
		comma=""
	fi
	if [ "$i" -le "$NUM_AUTHORITIES" ]; then
		json_validator="\"${address}\""
		json_validators_list="${json_validators_list}${comma}${json_validator}"
		json_account="\"${address}\": { \"balance\": \"10000000000000000000000000000000000000000000000000\" }"
		json_acccounts_list="${json_acccounts_list}${comma}${json_account}"
	fi
done

###############################################################################
### generate config files for authorities nodes ###############################
###############################################################################
for i in `seq 1 $NUM_AUTHORITIES`
do
	self_enode=${enode[i]}
	bootnodes=("${enode[@]/$self_enode}")
	bootnodes=$(join_by , ${bootnodes[@]})
	self_ssnode=${ssnode[i]}
	ssnodes=("${ssnode[@]/$self_ssnode}")
	ssnodes=$(join_by , ${ssnodes[@]})
	disable_ui="false"
	force_ui="true"
#	if [ "$i" -eq 1 ]; then
#		disable_ui="false"
#		force_ui="true"
#	fi
	config_contents="
# node#$i
# self_secret: ${secret[i]}
# self_public: ${public[i]}

[parity]
chain = \"poa_chain.json\"
base_path = \"db.poa_ss${i}\"

[ui]
force = $force_ui
disable = $disable_ui
port = ${ui_port[i]}

[rpc]
disable = $disable_ui
port = ${rpc_port[i]}

[websockets]
disable = $disable_ui
port = ${ws_port[i]}

[ipc]
disable = true

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
path = \"db.poa_ss${i}/secretstore\"

[mining]
author = \"${addresses[i]}\"
engine_signer = \"${addresses[i]}\"
force_sealing = true

[account]
unlock = [\"${addresses[i]}\"]
password = [\"password_file\"]
"
	echo "$config_contents" >"poa_ss${i}.toml"
done

###############################################################################
### generate config files for regular nodes ###################################
###############################################################################

for i in `seq 1 $NUM_REGULAR`
do
	j=$(($NUM_AUTHORITIES+$i))
	self_enode=${enode[j]}
	bootnodes=("${enode[@]/$self_enode}")
	bootnodes=$(join_by , ${bootnodes[@]})
	disable_ui="true"
	force_ui="false"
	config_contents="
# node#$j
# self_secret: ${secret[j]}
# self_public: ${public[j]}

[parity]
chain = \"poa_chain.json\"
base_path = \"db.poa_ss${j}\"

[ui]
force = $force_ui
disable = $disable_ui
port = ${ui_port[j]}

[rpc]
disable = $disable_ui
port = ${rpc_port[i]}

[websockets]
disable = $disable_ui
port = ${ws_port[i]}

[ipc]
disable = true

[dapps]
disable = $disable_ui

[network]
port = ${network_port[j]}
node_key = \"${secret[j]}\"
bootnodes = [$bootnodes]

[ipfs]
enable = false

[snapshots]
disable_periodic = true
"
	echo "$config_contents" >"poa_ss${j}.toml"
done

###############################################################################
### create chain config file ##################################################
###############################################################################
poa_chain_contents='
{
	"name": "POA",
	"dataDir": "POA",
	"engine": {
		"authorityRound": {
			"params": {
			"stepDuration": "4",
			"blockReward": "0x4563918244F40000",
				"validators" : {
					"list": [validators_list]
				},
				"validateScoreTransition": 1000000,
				"validateStepTransition": 1500000
			}
		}
	},
	"params": {
		"gasLimitBoundDivisor": "0x400",
		"registrar" : "0xfAb104398BBefbd47752E7702D9fE23047E1Bca3",
		"maximumExtraDataSize": "0x20",
		"minGasLimit": "0x1388",
		"networkID" : "0x2A",
		"forkBlock": 4297256,
		"forkCanonHash": "0x0a66d93c2f727dca618fabaf70c39b37018c73d78b939d8b11efbbd09034778f",
		"validateReceiptsTransition" : 1000000,
		"eip155Transition": 1000000,
		"validateChainIdTransition": 1000000
	},
	"genesis": {
		"seal": {
			"authorityRound": {
				"step": "0x0",
				"signature": "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
			}
		},
		"difficulty": "0x20000",
		"gasLimit": "0x5B8D80"
	},
	"accounts": {
		"0x0000000000000000000000000000000000000001": { "balance": "1", "builtin": { "name": "ecrecover", "pricing": { "linear": { "base": 3000, "word": 0 } } } },
		"0x0000000000000000000000000000000000000002": { "balance": "1", "builtin": { "name": "sha256", "pricing": { "linear": { "base": 60, "word": 12 } } } },
		"0x0000000000000000000000000000000000000003": { "balance": "1", "builtin": { "name": "ripemd160", "pricing": { "linear": { "base": 600, "word": 120 } } } },
		"0x0000000000000000000000000000000000000004": { "balance": "1", "builtin": { "name": "identity", "pricing": { "linear": { "base": 15, "word": 3 } } } },
		accounts_list
	}
}
'
poa_chain_contents="${poa_chain_contents/validators_list/$json_validators_list}"
poa_chain_contents="${poa_chain_contents/accounts_list/$json_acccounts_list}"

echo "$poa_chain_contents" > "poa_chain.json"

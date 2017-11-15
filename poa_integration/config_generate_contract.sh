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
solidity_validators_list=""
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
		solidity_validators_list="${solidity_validators_list}${comma}${address}"
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
### create validators set contract ############################################
###############################################################################

validators_set_contract='
pragma solidity ^0.4.8;

contract ValidatorSet {
    event InitiateChange(bytes32 indexed _parent_hash, address[] _new_set);

    function getValidators() constant returns (address[] _validators);
    function finalizeChange();
}

// Existing validators can give support to addresses.
// Support can not be added once MAX_VALIDATORS are present.
// Once given, support can be removed.
// Addresses supported by more than half of the existing validators are the validators.
// Malicious behaviour causes support removal.
// Benign misbehaviour causes supprt removal if its called again after MAX_INACTIVITY.
// Benign misbehaviour can be absolved before being called the second time.

contract MajorityList is ValidatorSet {

    // EVENTS

    event Report(address indexed reporter, address indexed reported, bool indexed malicious);
    event Support(address indexed supporter, address indexed supported, bool indexed added);
    event ChangeFinalized(address[] current_set);

    struct ValidatorStatus {
        // Is this a validator.
        bool isValidator;
        // Index in the validatorList.
        uint index;
        // Validator addresses which supported the address.
        AddressSet.Data support;
        // Keeps track of the votes given out while the address is a validator.
        address[] supported;
        // Initial benign misbehaviour time tracker.
        mapping(address => uint) firstBenign;
        // Repeated benign misbehaviour counter.
        AddressSet.Data benignMisbehaviour;
    }

    // System address, used by the block sealer.
    address SYSTEM_ADDRESS = 0xfffffffffffffffffffffffffffffffffffffffe;
    // Support can not be added once this number of validators is reached.
    uint public constant MAX_VALIDATORS = 30;
    // Time after which the validators will report a validator as malicious.
    uint public constant MAX_INACTIVITY = 6 hours;
    // Ignore misbehaviour older than this number of blocks.
    uint public constant RECENT_BLOCKS = 20;

    // STATE

    // Current list of addresses entitled to participate in the consensus.
    address[] public validatorsList;
    // Pending list of validator addresses.
    address[] pendingList;
    // Was the last validator change finalized.
    bool finalized;
    // Tracker of status for each address.
    mapping(address => ValidatorStatus) validatorsStatus;

    // CONSTRUCTOR

    // Used to lower the constructor cost.
    AddressSet.Data initialSupport;
    bool private initialized;

    // Each validator is initially supported by all others.
    function MajorityList() {
        pendingList = [validators_list];

        initialSupport.count = pendingList.length;
        for (uint i = 0; i < pendingList.length; i++) {
            address supporter = pendingList[i];
            initialSupport.inserted[supporter] = true;
        }
    }

    // Has to be called once before any other methods are called.
    function initializeValidators() uninitialized {
        for (uint j = 0; j < pendingList.length; j++) {
            address validator = pendingList[j];
            validatorsStatus[validator] = ValidatorStatus({
                isValidator: true,
                index: j,
                support: initialSupport,
                supported: pendingList,
                benignMisbehaviour: AddressSet.Data({ count: 0 })
            });
        }
        initialized = true;
        validatorsList = pendingList;
        finalized = false;
    }

    // CONSENSUS ENGINE METHODS

    // Called on every block to update node validator list.
    function getValidators() constant returns (address[]) {
        return validatorsList;
    }

    // Log desire to change the current list.
    function initiateChange() private when_finalized {
        finalized = false;
        InitiateChange(block.blockhash(block.number - 1), pendingList);
    }

    function finalizeChange() only_system_and_not_finalized {
        validatorsList = pendingList;
        finalized = true;
        ChangeFinalized(validatorsList);
    }

    // SUPPORT LOOKUP AND MODIFICATION

    // Find the total support for a given address.
    function getSupport(address validator) constant returns (uint) {
        return AddressSet.count(validatorsStatus[validator].support);
    }

    function getSupported(address validator) constant returns (address[]) {
        return validatorsStatus[validator].supported;
    }

    // Vote to include a validator.
    function addSupport(address validator) only_validator not_voted(validator) free_validator_slots {
        newStatus(validator);
        AddressSet.insert(validatorsStatus[validator].support, msg.sender);
        validatorsStatus[msg.sender].supported.push(validator);
        addValidator(validator);
        Support(msg.sender, validator, true);
    }

    // Remove support for a validator.
    function removeSupport(address sender, address validator) private {
        if (!AddressSet.remove(validatorsStatus[validator].support, sender)) { throw; }
        Support(sender, validator, false);
        // Remove validator from the list if there is not enough support.
        removeValidator(validator);
    }

    // MALICIOUS BEHAVIOUR HANDLING

    // Called when a validator should be removed.
    function reportMalicious(address validator, uint blockNumber, bytes proof) only_validator is_recent(blockNumber) {
        removeSupport(msg.sender, validator);
        Report(msg.sender, validator, true);
    }

    // BENIGN MISBEHAVIOUR HANDLING

    // Report that a validator has misbehaved in a benign way.
    function reportBenign(address validator, uint blockNumber) only_validator is_validator(validator) is_recent(blockNumber) {
        firstBenign(validator);
        repeatedBenign(validator);
        Report(msg.sender, validator, false);
    }

    // Find the total number of repeated misbehaviour votes.
    function getRepeatedBenign(address validator) constant returns (uint) {
        return AddressSet.count(validatorsStatus[validator].benignMisbehaviour);
    }

    // Track the first benign misbehaviour.
    function firstBenign(address validator) private has_not_benign_misbehaved(validator) {
        validatorsStatus[validator].firstBenign[msg.sender] = now;
    }

    // Report that a validator has been repeatedly misbehaving.
    function repeatedBenign(address validator) private has_repeatedly_benign_misbehaved(validator) {
        AddressSet.insert(validatorsStatus[validator].benignMisbehaviour, msg.sender);
        confirmedRepeatedBenign(validator);
    }

    // When enough long term benign misbehaviour votes have been seen, remove support.
    function confirmedRepeatedBenign(address validator) private agreed_on_repeated_benign(validator) {
        validatorsStatus[validator].firstBenign[msg.sender] = 0;
        AddressSet.remove(validatorsStatus[validator].benignMisbehaviour, msg.sender);
        removeSupport(msg.sender, validator);
    }

    // Absolve a validator from a benign misbehaviour.
    function absolveFirstBenign(address validator) has_benign_misbehaved(validator) {
        validatorsStatus[validator].firstBenign[msg.sender] = 0;
        AddressSet.remove(validatorsStatus[validator].benignMisbehaviour, msg.sender);
    }

    // PRIVATE UTILITY FUNCTIONS

    // Add a status tracker for unknown validator.
    function newStatus(address validator) private has_no_votes(validator) {
        validatorsStatus[validator] = ValidatorStatus({
            isValidator: false,
            index: pendingList.length,
            support: AddressSet.Data({ count: 0 }),
            supported: new address[](0),
            benignMisbehaviour: AddressSet.Data({ count: 0 })
        });
    }

    // ENACTMENT FUNCTIONS (called when support gets out of line with the validator list)

    // Add the validator if supported by majority.
    // Since the number of validators increases it is possible to some fall below the threshold.
    function addValidator(address validator) is_not_validator(validator) has_high_support(validator) {
        validatorsStatus[validator].index = pendingList.length;
        pendingList.push(validator);
        validatorsStatus[validator].isValidator = true;
        // New validator should support itself.
        AddressSet.insert(validatorsStatus[validator].support, validator);
        validatorsStatus[validator].supported.push(validator);
        initiateChange();
    }

    // Remove a validator without enough support.
    // Can be called to clean low support validators after making the list longer.
    function removeValidator(address validator) is_validator(validator) has_low_support(validator) {
        uint removedIndex = validatorsStatus[validator].index;
        // Can not remove the last validator.
        uint lastIndex = pendingList.length-1;
        address lastValidator = pendingList[lastIndex];
        // Override the removed validator with the last one.
        pendingList[removedIndex] = lastValidator;
        // Update the index of the last validator.
        validatorsStatus[lastValidator].index = removedIndex;
        delete pendingList[lastIndex];
        pendingList.length--;
        // Reset validator status.
        validatorsStatus[validator].index = 0;
        validatorsStatus[validator].isValidator = false;
        // Remove all support given by the removed validator.
        address[] toRemove = validatorsStatus[validator].supported;
        for (uint i = 0; i < toRemove.length; i++) {
            removeSupport(validator, toRemove[i]);
        }
        delete validatorsStatus[validator].supported;
        initiateChange();
    }

    // MODIFIERS

    modifier uninitialized() {
        if (initialized) { throw; }
        _;
    }

    function highSupport(address validator) constant returns (bool) {
        return getSupport(validator) > pendingList.length/2;
    }

    function firstBenignReported(address reporter, address validator) constant returns (uint) {
        return validatorsStatus[validator].firstBenign[reporter];
    }

    modifier has_high_support(address validator) {
        if (highSupport(validator)) { _; }
    }

    modifier has_low_support(address validator) {
        if (!highSupport(validator)) { _; }
    }

    modifier has_not_benign_misbehaved(address validator) {
        if (firstBenignReported(msg.sender, validator) == 0) { _; }
    }

    modifier has_benign_misbehaved(address validator) {
        if (firstBenignReported(msg.sender, validator) > 0) { _; }
    }

    modifier has_repeatedly_benign_misbehaved(address validator) {
        if (firstBenignReported(msg.sender, validator) - now > MAX_INACTIVITY) { _; }
    }

    modifier agreed_on_repeated_benign(address validator) {
        if (getRepeatedBenign(validator) > pendingList.length/2) { _; }
    }

    modifier free_validator_slots() {
        if (pendingList.length >= MAX_VALIDATORS) { throw; }
        _;
    }

    modifier only_validator() {
        if (!validatorsStatus[msg.sender].isValidator) { throw; }
        _;
    }

    modifier is_validator(address someone) {
        if (validatorsStatus[someone].isValidator) { _; }
    }

    modifier is_not_validator(address someone) {
        if (!validatorsStatus[someone].isValidator) { _; }
    }

    modifier not_voted(address validator) {
        if (AddressSet.contains(validatorsStatus[validator].support, msg.sender)) {
            throw;
        }
        _;
    }

    modifier has_no_votes(address validator) {
        if (AddressSet.count(validatorsStatus[validator].support) == 0) { _; }
    }

    modifier is_recent(uint blockNumber) {
        if (block.number > blockNumber + RECENT_BLOCKS) { throw; }
        _;
    }

    modifier only_system_and_not_finalized() {
        if (msg.sender != SYSTEM_ADDRESS || finalized) { throw; }
        _;
    }

    modifier when_finalized() {
        if (!finalized) { throw; }
        _;
    }

    // Fallback function throws when called.
    function() {
        throw;
    }
}

library AddressSet {
    // Tracks the number of votes from different addresses.
    struct Data {
        uint count;
        // Keeps track of who voted, prevents double vote.
        mapping(address => bool) inserted;
    }

    function count(Data storage self) constant returns (uint) {
        return self.count;
    }

    function contains(Data storage self, address voter) returns (bool) {
        return self.inserted[voter];
    }

    function insert(Data storage self, address voter) returns (bool) {
        if (self.inserted[voter]) { return false; }
        self.count++;
        self.inserted[voter] = true;
        return true;
    }

    function remove(Data storage self, address voter) returns (bool) {
        if (!self.inserted[voter]) { return false; }
        self.count--;
        self.inserted[voter] = false;
        return true;
    }
}
'
validators_set_contract="${validators_set_contract/validators_list/$solidity_validators_list}"

echo "$validators_set_contract" > "validators_set_contract.sol"
solcjs --optimize --bin validators_set_contract.sol >/dev/null
validators_set_contract_bin=`cat validators_set_contract_sol_MajorityList.bin`

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
					"safeContract": "0x0000000000000000000000000000000000000010"
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
		"0x0000000000000000000000000000000000000010": { "balance": "1", "constructor" : "0xvalidators_set_contract_bin" },
		accounts_list
	}
}
'
poa_chain_contents="${poa_chain_contents/validators_list/$json_validators_list}"
poa_chain_contents="${poa_chain_contents/accounts_list/$json_acccounts_list}"
poa_chain_contents="${poa_chain_contents/validators_set_contract_bin/$validators_set_contract_bin}"

echo "$poa_chain_contents" > "poa_chain.json"

# account/password
ACCOUNT="0x00a329c0648769A73afAc7F9381E08FB43dBEA72"
PASSWORD=""

# generate random key id
KEY_ID=`hexdump -n 32 -e '8/4 "%08X" 1 "\n"' /dev/random`

# sign KEY_ID
KEY_ID_SIGNATURE_REQUEST='{"jsonrpc": "2.0", "method": "secretstore_signRawHash", "params": ["'${ACCOUNT}'", "'${PASSWORD}'", "'${KEY_ID}'"], "id":1 }'
echo $KEY_ID_SIGNATURE_REQUEST

# generate server key
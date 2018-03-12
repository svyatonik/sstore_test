openssl ecparam -name secp256k1 -genkey -noout | openssl ec -text -noout > keyserver.key 2>nul
printf "PRIVATE KEY: 0x"
cat keyserver.key | grep priv -A 3 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^00//'
printf "\n\rPUBLIC KEY: 0x"
cat keyserver.key | grep pub -A 5 | tail -n +2 | tr -d '\n[:space:]:' | sed 's/^04//'
printf "\n\r"

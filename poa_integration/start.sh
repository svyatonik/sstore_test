NUM_NODES=`ls -1 | grep .toml | wc -l`

#NUM_NODES=$(($NUM_NODES-1))

for i in `seq 1 $NUM_NODES`
do
#	RUST_LOG=secretstore=trace,secretstore_net=trace ../parity --config ./poa_ss${i}.toml&
	RUST_LOG=sync=trace ../parity --config ./poa_ss${i}.toml&
done

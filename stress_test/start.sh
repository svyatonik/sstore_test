THRESHOLD=240
NUM_NODES=`ls -1 | grep .toml | wc -l`
echo $NUM_NODES

for i in `seq 1 $NUM_NODES`
do
	RUST_LOG=secretstore=trace,secretstore_net=trace ../parity --config ./dev_ss${i}.toml&
done
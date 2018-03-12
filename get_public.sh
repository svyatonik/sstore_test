# /*var Web3 = require('web3');
# var EC = require('elliptic').ec;
# var BN = require('bn.js');
# const keccak = require('keccakjs');
# 
# var ec = new EC('secp256k1');
# var web3 = new Web3(Web3.givenProvider || "http://localhost:8545");
# web3.eth.personal.sign(0xdeadbeef, "0x33a0B352470124757eab6ADbb7402537f2588b93", "password")
# //	.then((signature) => web3.eth.personal.ecRecover("0xdeadbeef", signature))
# 	.then((signature) => {
# 		var r = new BN(signature.substr(2, 64), 16);
# 		var s = new BN(signature.substr(66, 64), 16);
# 		var v = new BN(signature.substr(130, 2), 16) - 27;
# 		console.log(signature);
# 		console.log(r.toString(16));
# 		console.log(s.toString(16));
# 		console.log(v.toString(16));
# 
# 
# 		var hash = new keccak(256);
# 		hash.update('\x19Ethereum Signed Message:\n4')
# 		//hash.update(new Buffer('42004200', 'hex'))
# 		hash.update(new Buffer('0xdeadbeef', 'hex'));
# 		var binHash = hash.digest('hex'); // hex output
# 
# 		var public = ec.recoverPubKey(binHash, { r: r, s: s }, v, 'hex');
# 		return "0x" + public.x.toString(16) + public.y.toString(16);
# 	})
# 	.then(console.log);*/
./ethstore public 31A5A0fef65ad8D3afA8848Da4ff277Fdc663162 password.file --dir poa_integration/db.poa_ss1/keys/POA

#!/usr/bin/python2.7
import secp256k1 # install by typing `pip install secp256k1`

key_id = bytes(bytearray.fromhex('0000000000000000000000000000000000000000000000000000000000000001'))
sk = secp256k1.PrivateKey()
sig_raw = sk.ecdsa_sign_recoverable(key_id, raw=True)
sig_der = sk.ecdsa_recoverable_serialize(sig_raw)
pub_der = sk.pubkey.serialize(compressed=False)

print 'SECRET: ' + ''.join('{:02x}'.format(ord(c)) for c in sk.private_key)
print 'PUBLIC: ' + ''.join('{:02x}'.format(ord(c)) for c in pub_der[1:])
print 'SIGNATURE: ' + ''.join('{:02x}'.format(ord(c)) for c in sig_der[0]) + '{:02x}'.format(sig_der[1])
#!/bin/bash
RUST_LOG=secretstore=trace,secretstore_net=trace ./parity --config dev_ss1.toml&
RUST_LOG=secretstore=trace,secretstore_net=trace ./parity --config dev_ss2.toml&
RUST_LOG=secretstore=trace,secretstore_net=trace ./parity --config dev_ss3.toml&

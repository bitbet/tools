#!/bin/bash

block1=$1
export  BC_LINE_LENGTH=10000
hash1=`bitcoin-cli getblockhash $block1 | tr a-z A-Z`
block2=`echo mod=412000\;scale=0\;obase=10\;ibase=16\;$hash1\%mod | bc -l`
hash2=`bitcoin-cli getblockhash $block2 | tr a-z A-Z`
combined=`echo obase=16\;ibase=16\;$hash1*$hash2 | bc -l | tr A-Z a-z`
sha256=`printf '%s' $combined | sha256sum -b | cut -d' ' -f1 | tr a-z A-Z`
lottery=`echo mod=2\;scale=0\;obase=10\;ibase=16\;$sha256\%mod | bc -l`
echo $lottery


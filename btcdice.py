#!/usr/bin/python

# Stuff we need
import sys
import hashlib
import subprocess

# Bitcoin RPC
def btcCommand(args):
    cmd = ["bitcoin-cli"] + args
    output = subprocess.check_output(cmd)
    return output.rstrip('\n')

# Get the hash of a block
def getBlockHash(block):
    return btcCommand(["getblockhash", str(block)])

# Compute lottery
def lottery(blockInt, verbose=0):
    modulo = 412000
    blockHashStr = getBlockHash(blockInt)
    blockHashInt = int(blockHashStr, 16)
    siblingBlockInt = (blockHashInt % modulo)
    siblingBlockHashStr = getBlockHash(siblingBlockInt)
    siblingBlockHashInt = int(siblingBlockHashStr, 16)
    combinedHashesInt = (blockHashInt * siblingBlockHashInt)
    combinedHashesStr = ('%x' % combinedHashesInt)
    sha256HexStr = hashlib.sha256(combinedHashesStr).hexdigest()
    sha256Int = int(sha256HexStr, 16)
    result = (sha256Int % 2)

    if verbose:
        print ""
        print "Lottery details for block %d:" % blockInt
        print "    hash(block %7d) =                                  %s (...%s)" % (blockInt, blockHashStr, '{0:04b}'.format(blockHashInt % 0x10))
        print "           siblingBlock = (hash %% %d) = %d" % (modulo, siblingBlockInt)
        print "    hash(block %7d) =                                  %s (...%s)" % (siblingBlockInt, siblingBlockHashStr, '{0:04b}'.format(siblingBlockHashInt % 0x10))
        print "        combined hashes = %s (...%s)" % (combinedHashesStr, '{0:04b}'.format(combinedHashesInt % 0x10))
        print "sha256(combined hashes) =                                  %s (...%s)" % (sha256HexStr, '{0:04b}'.format(sha256Int % 0x10))
        print "                lottery = %d" % (result)
        print ""

    return result

# Make sure that bitcoin is up and running
blockOneHash = '00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048'
if blockOneHash!=getBlockHash(1):
    raise ValueError('could not verify hash of bitcoin block #1, something is likely wrong with your bitcoin setup')

# Parse command line
if 2!=len(sys.argv):
    raise ValueError('usage: lottery.py <block number>')

# Basic check that we're getting a decent number
blockInt = int(sys.argv[1])
blockValid = (1<=blockInt and blockInt<=10000000)
if not blockValid:
    raise ValueError('block number ' + argv[1] + ' is not a valid block number')

# Display lottery
lottery(blockInt, 1)


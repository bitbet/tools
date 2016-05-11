#!/usr/bin/python

"""

    Reproducible, bitcoin-based fair coin throw
    -------------------------------------------

    This code is used to implement provably fair lottery
    bets on the Bitcoin betting site https://bitbet.us

    This requires:
        - bitcoin-cli in the $PATH
        - bitcoind up with a complete blockchain

    Usage:

        python btcdice.py [bitcoin block id]

    Example:

        $ python btcdice.py 395432
        block =  395432 , sibling block =  129625 , nbLoops =  217  lottery =  0

        $ python btcdice.py
        block =  1 , sibling block =  183933 , nbLoops =  218  lottery =  0
        p(0) = 1.00000
        block =  2 , sibling block =  231451 , nbLoops =  110  lottery =  1
        p(0) = 0.50000
        block =  3 , sibling block =  271289 , nbLoops =  44  lottery =  1
        p(0) = 0.33333
        block =  4 , sibling block =  68524 , nbLoops =  94  lottery =  0
        p(0) = 0.50000
        block =  5 , sibling block =  367840 , nbLoops =  59  lottery =  1
        p(0) = 0.40000
        block =  6 , sibling block =  198273 , nbLoops =  176  lottery =  0
        p(0) = 0.50000
        ...

    The best way to assess the fairness of the dice is simply to read the code below and
    understand what it does, which is really not rocket science.

    One thing worth observing is the fact that the very last step of the algorithm is a
    SHA512 hash step, an algorithm designed - among other things - to produce uniformly
    distributed bits.
 
    Note that this was designed to give a sizable headache to a miner that would try to
    mine a block yielding a specific outcome for this algorithm. Not that this is a
    particularly likely scenario, but it was kind of a fun exercise to design.

    The three key hurdles introduced here are:

        - hash functions used are heavy and slow by design

        - while smart crypto algorithms typically try to be data-independent to prevent
          side-channel attacks, we forcibly introduce data dependencies in our algorithm:
          we hash the hashes a number of times that is dependent on the very first hash.

          This nicely reduces naive massively parallel attacks as the time taken by the
          algorithm becomes hard to predict.

        - from the given block id, we compute via slow hashes, the id of a "sibling" block
          in the range [1, 400000), and we XOR the hash of the given block with that of the
          sibling block. This forces a would-be attacker to keep the entire hash database
          in memory. Not a very easy thing to pull off on an ASIC.

        - as mentioned earlier, the XOR is fed to one last SHA512 step to ensure lottery
          uniformity.

    This is not an FIH (fits-in-head) algorithm, but it'll have to do for now.

    The code will, when launched with no argument compute the lottery outcome on all blocks
    from 1 to 400000 and output the observed odds of 'Yes' vs. 'No.

    Finally, if you feel that you have somehow managed to identify some sort of predictable
    bias in the formula, or if you somehow feel strong in your ability to predict the outcome,
    then well, congratulations !!!!

    The path forward is as clear as can be: keep your discovery secret and please come
    and place wagers on https://bitbet.us on the lottery bets powered by this algorithm,
    you are sure to profit !

"""

# Stuff we need
import sys
import hashlib
import subprocess

# Constants
finalMod = 2
maxNbLoops = 257
bitChopper = 310889
maxBackBlock = 400000
twoToThe255Minus19 = pow(2, 255) - 19
blockOneHash = '00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048';

# Get the hash of a bitcoin block via RPC
def getBlockHash(block):
    return subprocess.check_output([
        "bitcoin-cli",
        "getblockhash",
        str(block)
    ]).rstrip('\n')

# Core hash function, designed to be fairly slow
def slowBaseHash(data):

    if not (type(data) is long):
        raise ValueError('data should be a (big) int not a %s' % type(data));
    
    dataStr = str(data)                                     # -> base10 string
    dataSHA512Hex = hashlib.sha512(dataStr).hexdigest()     # -> sha512 -> base16 string
    x = int(dataSHA512Hex, 16)                              # -> large int
    x = (x*x*x + 486662*x*x + x)                            # -> some polynomial
    x = (x % twoToThe255Minus19)                            # -> modulo some prime
    x = (x // bitChopper)                                   # -> chop a few bits
    xStr = str(x)                                           # -> base10 string
    xSHA512Hex = hashlib.sha512(xStr).hexdigest()           # -> sha512 -> base16 string
    return int(xSHA512Hex, 16)                              # -> large int

# Outer hash function, designed to be data dependent
def slowDataDependentHash(data):
    data = slowBaseHash(data)                               # -> coreHash
    nbLoops = (data // bitChopper)                          # -> chop a few bits
    nbLoops = nbLoops % maxNbLoops                          # -> infer # of loops
    for x in range(0, nbLoops):                             # -> iterate hash by # of loops
        data = slowBaseHash(data)
    return (data, nbLoops)

# Lottery function by combining two block hashes
def lottery(blockId, nbOutcomes):

    # Grab hash of block via bitcoin RPC
    hash1 = getBlockHash(blockId)
    hash1Num = int(hash1, 16)

    # Feed it to slow hash function to find sibling block
    (block2, nbLoops) = slowDataDependentHash(hash1Num)
    block2 = block2 % maxBackBlock
    block2 = str(block2)

    # Grab hash of sibling block via bitcoin RPC
    hash2 = getBlockHash(block2)
    hash2Num = int(hash2, 16)

    # XOR hash of current and sibling blocks
    hashXOR = (hash1Num ^ hash2Num)
    hashXORStr = str(hashXOR)

    # One final pass of SHA512 for uniformity
    xorSHA512Hex = hashlib.sha512(hashXORStr).hexdigest()
    final = int(xorSHA512Hex, 16)

    # Map to [0, nbOutcomes)
    final = final % nbOutcomes
    return (final, block2, nbLoops)

# Parse command line
fromBlock = 1;
toBlock = 411157;
if 1<len(sys.argv):
    fromBlock = int(sys.argv[1]);
    toBlock = fromBlock

# Check that bitcoin is up and running
if not (blockOneHash==getBlockHash('1')):
    raise ValueError('could not verify hash of bitcoin block #1, something is likely wrong with your bitcoin setup')

# Run lottery on all blocks and gather basic stats
count = 0
histo = [0] * finalMod
for blockId in range(fromBlock, 1+toBlock):

    # Draw lottery
    (outcome, sibling, nbLoops) = lottery(blockId, finalMod)

    # Show result
    print 'block = ', blockId, ', sibling block = ', sibling, ', nbLoops = ', nbLoops, ' lottery = ', outcome

    # Update stats
    histo[outcome] += 1
    count += 1

    if fromBlock<toBlock:
        print "p(0) = %.5f" % (histo[0] / float(count))


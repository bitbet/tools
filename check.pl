#!/usr/bin/perl

=pod

    The algorithm for computing a contract outcome on https://bibet.us

        Principle:
        ==========

            . As a systematic first step, a fee is deducted from all monies wagered

            . The deducted fee depends on the date of the wager: for a wager placed strictly before 01.08.2016, it is 1%, and after it is 2%
            . The deducted fee is irreversible, regardless of the wager becoming a win, a loss or a refund
            . The net wager (wager amount after fee is deducted) is used in all subsequent calculations

            . When the contract outcome is known, in a first pass:

                . Every wager is sorted in exactly one of 3 buckets:
                    - Refunded wager
                    - Lost wager
                    - Won wager

                . For each refunded wager, the net wager amount is refunded, and does not affect the rest of the calculation.
                . For each lost wagers, the net wager amount is added to the "Loser's Pot".
                . For each won wagers, the net wager amount, multiplied by the wager weight is added to the "Weighted Winner's Pot"

            . In a second pass, the final payout of the won wagers is calculated as the sum of:

                - the initial wager minus bitbet's fee
                - the wager's share of the loser's pot, where the share of the loser's pot is:

                        (netWagerAmount * wagerWeight) / (weightedWinnerPot)

        Example:
        ==========

                . Contract data:
                    . Mary bet  1 BTC at weight 99'999 and won
                    . John bet  2 BTC at weight 80'000 and won
                    . Alex bet  5 BTC at weight 60'000 and lost
                    . Bob  bet 10 BTC at weight  1'000 after the event deadline and gets a refund

                . Fee is deducted:
                    Mary's  net bet is  1.00 * 0.98 = 0.98
                    John's  net bet is  2.00 * 0.98 = 1.96
                    Alice's net bet is  5.00 * 0.98 = 4.90
                    Bob's   net bet is 10.00 * 0.98 = 9.80

                . Weighted winner's pot is Mary and John's bets: 99999*0.98 + 80000*1.96 = 254799.02
                . Loser's pot is just Alice's bet: 4.90
                . Bob's bet is a refund, he gets 9.80 back

                . Mary's share of the loser's pot is (0.98*99999) / 254799.02 ~= 38.46 % , i.e. 1.88460379 BTC
                . John's share of the loser's pot is (1.96*80000) / 254799.02 ~= 61.54 %. i.e. 3.01539621 BTC

                . Mary's  final payout  is 0.98 (her net bet) + 1.88460379 (her winnings) = 2.86460379 BTC
                . Johns's final payout is 1.96 (his net bet) + 3.01539621 (his winnings) = 4.97539621 BTC

=cut

# Stuff we need
# =============
use strict;
use warnings;
use Math::BigRat;
print "\n";

# Command line
# ============
my($outcome) = 'Yes';
$outcome = $ARGV[0] if(0<scalar(@ARGV));

# Vig is 2% after 01.08.2016
# ==========================
sub vig {
    my($date) = shift;
    my($d, $m, $y) = split(/-/, $date);
    my($twoPercent) = Math::BigRat->new('2/100');
    my($onePercent) = Math::BigRat->new('1/100');
    return (16<=$y && 8<=$m) ? $twoPercent : $onePercent;
}

# Load bets from file bet.txt (file should be a cut and paste from bet table on web page)
# ========================================================================================
my($i) = 1;
my($bets) = [];
my($scale) = Math::BigRat->new('100000000');
open(Z, "<bet.txt") || die("file bet.txt is missing\n");
    while(<Z>) {
        chomp;
        s/\`//g;
        s/[ ]+$//;
        s/[ ]+/ /g;
        if(/^[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} ([A-Za-z])+/) {
            my($date, $time, $side, $weight, $btcIn, $addieIn, $btcOut, $addieOut) = split(/ /);
            my($bet) = {};
            $bet->{id} = $i++;
            $bet->{date} = $date;
            $bet->{time} = $time;
            $bet->{side} = $side;
            $bet->{addieIn} = $addieIn;
            $bet->{addieOut} = $addieOut;
            $bet->{weight} = Math::BigRat->new($weight);
            $bet->{btcIn} = $scale * Math::BigRat->new($btcIn);
            $bet->{btcOut} = $scale * Math::BigRat->new($btcOut);
            push(@{$bets}, $bet);
        }
    }
close(Z);

# First pass on bets: compute weighted winner pot
# ===============================================
my($bet);
my($loserPot) = Math::BigRat->bzero();
my($weightedWinnerPot) = Math::BigRat->bzero();
my($notOutcome) = ('No' eq $outcome ? 'Yes' : 'No');
foreach $bet (@{$bets}) {

    # Load relevant data from this bet
    # ================================
    my($btcIn) = $bet->{btcIn};         # Gross amount wagered
    my($vig) = vig($bet->{date});       # Date dependent vig
    my($weight) = $bet->{weight};       # Weight of bet
    my($fee) = ($vig * $btcIn);         # BitBet's fee
    my($side) = $bet->{side};           # Side taken by user
    my($netBtcIn) = ($btcIn - $fee);    # Net amount wagered (BitBet fee applies to all amounts wagered)
    $bet->{vig} = $vig;

    # Bet is either a refund, a win or a loss
    # =======================================
    if($side eq 'Refund') {
        # Bet is a refund => doesn't affect result
        # ========================================
    } elsif($side eq $notOutcome) {
        # Bet is a lost bet
        # =================
        $loserPot += $netBtcIn;
    } elsif($side eq $outcome) {
        # Bet is a winning bet, add to weighted winner pot
        # ================================================
        $weightedWinnerPot += ($weight * $netBtcIn);
    } else {
        die('input is corrupted');
    }
}

# Second pass on bets: compute winnings and refunds
# =================================================
foreach $bet (@{$bets}) {

    # Load relevant data from this bet
    # ================================
    my($btcIn) = $bet->{btcIn};         # Gross amount wagered
    my($vig) = vig($bet->{date});       # Date dependent vig
    my($weight) = $bet->{weight};       # Weight of bet
    my($fee) = ($vig * $btcIn);         # BitBet's fee
    my($side) = $bet->{side};           # Side taken by user
    my($netBtcIn) = ($btcIn - $fee);    # Net amount wagered (BitBet fee applies to all amounts wagered)

    # Bet is either a refund, a win or a loss
    # =======================================
    if($side eq 'Refund') {
        # Bet is a refund => doesn't affect result
        # ========================================
        $bet->{computedOut} = $netBtcIn;
        $bet->{outcome} = "RFND";
    } elsif($side eq $notOutcome) {
        # Bet is a lost bet
        # =================
        $bet->{computedOut} =  Math::BigRat->bzero();
        $bet->{outcome} = "LOSE";
    } elsif($side eq $outcome) {
        # Bet is a winning bet, compute winnings
        # ======================================
        my($share) = ($netBtcIn * $weight) / $weightedWinnerPot;    # Weighted share of loser's pot
        my($winnings) = ($share * $loserPot);                       # Weighted winnings from loser's pot
        my($out) = ($winnings + $netBtcIn);                         # Add winner's net initial bet
        $bet->{computedOut} = $out;
        $bet->{outcome} = "WIN";
    } else {
        die('input is corrupted');
    }
}

# Left pad a string to reach length N
# ==================================
sub fmt {
    my($s) = shift;
    my($n) = shift;
    my($r) = shift;
    my($d) = $n - length($s);
    if(0<$d) {
        my($pad) = (' ' x $d);
        if($r) {
            $s = $s.$pad;
        } else {
            $s = $pad.$s;
        }
    }
    return $s;
}

# Convert satoshis to BTC
# =======================
sub sat {
    my($x) = shift;
    return '   NaN       ' if($x =~ /NaN/);
    return '   NaN       ' if($x->is_nan());

    $x = $x->bfloor();
    $x = $x / $scale;
    return sprintf("%13.8f", $x->as_float());
}

# Compute final bet outcome and if bet was already resolved on page, double-check result
# ======================================================================================
print <<'EOF';
BETID   FEE   DATE       TIME    STATUS   SIDE   WEIGHT   BTCIN        ADDIN    BTCOUT       ADDOUT   COMPUTED     CHECK
=============================================================================================================================
EOF
foreach $bet (@{$bets}) {

    my($check);
    my($delta);
    my($out) = $bet->{btcOut};
    if($out->is_nan()) {
        $out = 'NaN';
        $delta = 'NaN';
        $check = "unresolved";
    } else {
        my($small) = Math::BigRat->new('1.0');
        $delta = ($bet->{computedOut} - $out);
        $check = ($small<$delta->babs() ? "WRONG" : "OK");
    }

    if(1) {
        printf(
            "%05d   %.0f%%    %s   %s   %s     %s%5d %s   %s %s   %s %s   %s\n",
            $bet->{id},
            $bet->{vig}*100.0,
            $bet->{date},
            $bet->{time},
            fmt($bet->{outcome}, 4, 1),
            fmt($bet->{side}, 7, 1),
            $bet->{weight},
            sat($bet->{btcIn}),
            fmt($bet->{addieIn}, 5, 1),
            sat($out),
            fmt($bet->{addieOut}, 5, 1),
            sat($bet->{computedOut}),
            $check
        );
    }
}
printf("\n");


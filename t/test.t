#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Test::More;
use Test::Fatal;

use DBIx::Pool;
use Scalar::Util qw(blessed);

my $pool = DBIx::Pool->new;
ok blessed($pool), 'constructor';

my $fake_dbh = {};
$pool->add(blah => $fake_dbh);

my $dbh = $pool->get('blah');
is $fake_dbh, $dbh, 'get() a handle added via add()'; # wrapper not implemented yet

like exception { $pool->get('blah') }, qr/pool is empty/, 'get() on empty pool fails';

subtest 'get() order' => sub {
    my $straight;
    my $reverse;
    my $tested;

    # chance of failing is 2^100 :)
    for (1 .. 100) {
        my $dbh1 = {};
        my $dbh2 = {};
        $pool->add(blah => $_) for ($dbh1, $dbh2);
        my ($got1, $got2) = map { $pool->get('blah') } (1,2);

        if ($dbh1 eq $got1 and $dbh2 eq $got2) {
            $straight++;
        }
        elsif ($dbh1 eq $got2 and $dbh2 eq $got1) {
            $reverse++;
        }
        else {
            fail "unexpected result from get()";
            $tested++;
            last;
        }

        if ($straight and $reverse) {
            pass "get() returns connections in random order";
            $tested++;
            last;
        }
    }

    fail "get() returns connections in random order" unless $tested;
};

done_testing;


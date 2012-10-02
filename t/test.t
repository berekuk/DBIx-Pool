#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use parent qw(Test::Class);
use Test::More;
use Test::Fatal;

use DBIx::Pool;
use Scalar::Util qw(blessed);

sub constructor :Tests {
    my $pool = DBIx::Pool->new;
    ok blessed($pool);
}

sub dbh {
    my $attr = shift || {};
    return DBI->connect('DBI:Safe:', undef, undef,
        {
         dbi_connect_args => ['dbi:ExampleP:dummy', '', ''],
         PrintError => 1, RaiseError => 1, AutoCommit => 1,
         %{$attr},
        }
    );
}

sub get :Tests {
    my $pool = DBIx::Pool->new;

    my $dbh = dbh;
    $pool->add(blah => $dbh);

    my $pool_dbh = $pool->get('blah');
    is $pool_dbh->{x_pool_dbh}, $dbh, 'get() a handle added via add()';

    like exception { $pool->get('blah') }, qr/pool is empty/, 'get() on empty pool fails';
}

sub get_and_give_back :Tests {
    my $pool = DBIx::Pool->new;

    my $dbh = dbh;
    $pool->add(blah => $dbh);

    my $pool_dbh = $pool->get('blah');
    my $str = "$pool_dbh";
    undef $pool_dbh;

    $pool_dbh = $pool->get('blah');
    is $str, "$pool_dbh", 'repeated get() returns the same object';
}

sub get_name_parameter :Tests {
    my $pool = DBIx::Pool->new;

    $pool->add(blah => dbh);
    $pool->add(blah => dbh);

    my @dbh;
    ok exception { push @dbh, $pool->get('foo') };
    ok not exception { push @dbh, $pool->get('blah') };
    ok not exception { push @dbh, $pool->get('blah') };
    ok exception { push @dbh, $pool->get('blah') };
};

sub get_order :Tests {

    my $straight;
    my $reverse;
    my $tested;

    # chance of failing is 2^100 :)
    for (1 .. 100) {
        # clear is broken - taken connections return to pool anyway
        # so we have to create a new pool on each iteration
        my $pool = DBIx::Pool->new;

        my $dbh1 = dbh;
        my $dbh2 = dbh;
        $pool->add(blah => $_) for ($dbh1, $dbh2);
        my ($got1, $got2) = map { $pool->get('blah') } (1,2);
        $_ = $_->{x_pool_dbh} for ($got1, $got2);

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
}

# TODO - test memory leaks
# TODO - test ->clear

__PACKAGE__->new->runtests;

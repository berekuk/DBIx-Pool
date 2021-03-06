#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use parent qw(Test::Class);
use Test::More;
use Test::Fatal;

use DBIx::Pool;
use Scalar::Util qw(blessed refaddr);

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
    is $pool_dbh, $dbh, 'get() a handle added via add()';
    ok $dbh->isa('DBIx::Pool::Handle'), 'original dbh reblessed';

    like exception { $pool->get('blah') }, qr/pool is empty/, 'get() on empty pool fails';
}

sub get_and_give_back :Tests {
    my $pool = DBIx::Pool->new;

    $pool->add(blah => dbh);

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
        my $pool = DBIx::Pool->new;

        my $dbh1 = dbh;
        my $dbh2 = dbh;
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
}

sub connector :Tests {
    my $pool = DBIx::Pool->new(
        connector => sub {
            my $name = shift;
            return dbh if $name eq 'blah';
            die "base '$name' not found";
        }
    );
    my $dbh = $pool->get('blah');
    ok $dbh->isa('DBIx::Pool::Handle');

    like exception { $pool->get('foo') }, qr/not found/;
}

sub size :Tests {
    my $pool = DBIx::Pool->new(
        connector => sub {
            my $name = shift;
            return dbh if $name eq 'blah';
            die "base '$name' not found";
        },
    );

    is $pool->size, 0;
    is $pool->free_size, 0;
    is $pool->taken_size, 0;

    $pool->add('foo' => dbh);
    $pool->add('foo' => dbh);
    $pool->add('bar' => dbh);
    is $pool->size, 3;
    is $pool->free_size, 3;
    is $pool->taken_size, 0;

    my $dbh = $pool->get('foo');
    my $dbh2 = $pool->get('bar');
    is $pool->size, 3;
    is $pool->free_size, 1;
    is $pool->taken_size, 2;

    my $dbh3 = $pool->get('blah');
    my $dbh4 = $pool->get('blah');
    is $pool->size, 5;
    is $pool->free_size, 1;
    is $pool->taken_size, 4;

    undef $_ for $dbh, $dbh2, $dbh3, $dbh4;

    is $pool->size, 5;
    is $pool->free_size, 5;
    is $pool->taken_size, 0;
}

sub max_size :Tests {
    my $pool = DBIx::Pool->new(
        max_size => 3,
        connector => sub {
            my $name = shift;
            return dbh if $name eq 'blah';
            die "base '$name' not found";
        },
    );

    $pool->add('foo' => dbh);
    $pool->add('foo' => dbh);
    $pool->add('foo' => dbh);
    like exception { $pool->add('foo' => dbh) }, qr/exceeded/;
    like exception { $pool->get('blah') }, qr/exceeded/;
}

sub memory_leak :Tests {

    return 'memory leak test is linux-only' unless $^O eq 'linux';

    my $get_mem_usage = sub {
        my $file = "/proc/$$/statm";
        open my $fh, '<', $file or die "Can't open $file: $!";
        my $stat = do { local $/; <$fh> };
        my ($mem) = $stat =~ /^(\d+)/;
        return $mem;
    };

    my $do_once = sub {
        dbh();
        my $pool = DBIx::Pool->new;
        $pool->add('foo' => dbh) for 1..3;
        my $dbh = $pool->get('foo');
    };

    $do_once->();
    my $mem_usage = $get_mem_usage->();
    $do_once->() for 1 .. ($ENV{N} || 1000);

    cmp_ok($get_mem_usage->() - $mem_usage, '<', 10);
}

__PACKAGE__->new->runtests;

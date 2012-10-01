#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use Test::More;

use DBIx::Pool;
use Scalar::Util qw(blessed);

my $pool = DBIx::Pool->new;
ok blessed($pool), 'constructor';

my $fake_dbh = {};
$pool->add(blah => $fake_dbh);

my $dbh = $pool->get('blah');
is $fake_dbh, $dbh, 'get() a handle added via add()'; # wrapper not implemented yet

done_testing;


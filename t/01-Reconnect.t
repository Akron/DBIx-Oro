#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Data::Dumper;
use File::Temp qw/:POSIX/;

$|++;

our (@ARGV, %ENV);
use lib (
  't',
  'lib',
  '../lib',
  '../../lib',
  '../../../lib'
);

use DBTestSuite;

my $suite = DBTestSuite->new($ENV{TEST_DB} || $ARGV[0] || 'SQLite');

# Configuration for this database not found
unless ($suite) {
  plan skip_all => 'Database not properly configured';
  exit(0);
};

# Start test
plan tests => 25;

use_ok 'DBIx::Oro';

# Initialize Oro
my %post_param;

# Make a real database for reconnect tests
if ($suite->driver eq 'SQLite') {
  # Real DB:
  $post_param{file} = tmpnam();
};

my $oro = DBIx::Oro->new(
  %{ $suite->param },
  %post_param
);

ok($oro, 'Handle created');

ok($suite->oro($oro), 'Add to suite');

ok($suite->init(qw/Name Content Book/), 'Init');

END {
  ok($suite->drop, 'Transaction for Dropping') if $suite;
};

ok($oro->select('Name'), 'Table Name exists');
ok($oro->select('Content'), 'Table Content exists');
ok($oro->select('Book'), 'Table Book exists');

ok($oro->insert(Content => {
  title => 'Test',
  content => 'Value 1'
}), 'Before disconnect');

ok($oro->dbh->disconnect, 'Disonnect');

# Driver test
is($oro->driver, $suite->driver, 'Driver');

ok($oro->insert(Content => {
  title => 'Test', content => 'Value 2'
}), 'Reconnect');

ok($oro->on_connect(
  sub {
    ok(1, 'on_connect release 1')}
), 'on_connect');


ok($oro->on_connect(
  testvalue => sub {
    ok(1, 'on_connect release 2')}
), 'on_connect');

ok(!$oro->on_connect(
  testvalue => sub {
    ok(0, 'on_connect release 3')}
), 'on_connect');

ok($oro->dbh->disconnect, 'Disconnect');

ok($oro->insert(Content => {
  title => 'Test', content => 'Value 3'
}), 'Reconnect');

ok($oro = DBIx::Oro->new(%{ $suite->param }, %post_param), 'Init temp db');

ok($suite->oro($oro), 'Set oro to suite');

my ($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql, 'No last SQL');
ok(!$last_sql_cache, 'No Cache');

# deelete all

ok($oro->insert(Content => {
  title => 'Test', content => 'Value 1'
}), 'Before disconnect');

ok($oro->dbh->disconnect, 'Disonnect');




__END__

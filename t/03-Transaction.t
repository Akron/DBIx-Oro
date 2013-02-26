#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 34;
use Data::Dumper;

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

use_ok 'DBIx::Oro';

# Initialize Oro
my $oro = DBIx::Oro->new(
  %{ $suite->param }
);

ok($oro, 'Handle created');

ok($suite->oro($oro), 'Add to suite');

ok($suite->init(qw/Content/), 'Init');

END {
  ok($suite->drop, 'Transaction for Dropping') if $suite;
};

# ---


# Insert:
ok($oro->insert(Content => { title => 'Check!',
			     content => 'This is content.'}), 'Insert');

ok($oro->insert(Content =>
		  { title => 'Another check!',
		    content => 'This is second content.' }), 'Insert');

ok($oro->insert(Content =>
		  { title => 'Check!',
		    content => 'This is third content.' }), 'Insert');


my ($rv, $sth) = $oro->prep_and_exec('SELECT count("*") as count FROM Content');
ok($rv, 'Prep and Execute');
is($sth->fetchrow_arrayref->[0], 3, 'Prep and exec');

$sth->finish;

ok($oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->begin_work;
ok(!$oro->dbh->{AutoCommit}, 'Transaction');

foreach my $x (1..10) {
  $oro->insert(Content => { title => 'Transaction',
			    content => 'Das ist der '.$x.'. Eintrag'});
};

ok(!$oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->commit;
ok($oro->dbh->{AutoCommit}, 'Transaction');

($rv, $sth) = $oro->prep_and_exec('SELECT count("*") as count FROM Content');
ok($rv, 'Prep and Execute');
is($sth->fetchrow_arrayref->[0], 13, 'Fetch row.');
$sth->finish;

ok($oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->begin_work;
ok(!$oro->dbh->{AutoCommit}, 'Transaction');

foreach my $x (1..10) {
  $oro->insert(Content => { title => 'Transaction',
			    content => 'Das ist der '.$x.'. Eintrag'});
};

ok(!$oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->rollback;
ok($oro->dbh->{AutoCommit}, 'Transaction');

($rv, $sth) = $oro->prep_and_exec('SELECT count("*") as count FROM Content');
ok($rv, 'Prep and Execute');
is($sth->fetchrow_arrayref->[0], 13, 'Fetch row.');
$sth->finish;

is($oro->count('Content'), 13, 'count');

my $load = $oro->load('Content' => ['count(*):number']);
is($load->{number}, 13, 'AS feature');

ok($oro->txn(
  sub {
    foreach (1..100) {
      $oro->insert(Content => { title => 'Check'.$_ });
    };
    return 1;
  }), 'Transaction');

is($oro->count('Content'), 113, 'Count');

ok(!$oro->txn(
  sub {
    foreach (1..100) {
      $oro->insert(Content => { title => 'Check'.$_ });
      return -1 if $_ == 50;
    };
    return 1;
  }), 'Transaction');

is($oro->count('Content'), 113, 'Count');

# Nested transactions:

ok($oro->txn(
  sub {
    my $val = 1;

    foreach (1..100) {
      $oro->insert(Content => { title => 'Check'.$val++ });
    };

    ok(!$oro->txn(
      sub {
	foreach (1..100) {
	  $oro->insert(Content => { title => 'Check'.$val++ });
	  return -1 if $_ == 50;
	};
      }), 'Nested Transaction 1');

    ok($oro->txn(
      sub {
	foreach (1..100) {
	  $oro->insert(Content => { title => 'Check'.$val++ });
	};
	return 1;
      }), 'Nested Transaction 2');

    return 1;
  }), 'Transaction');

is($oro->count('Content'), 313, 'Count');


# Local return
ok($oro->txn(
  sub {
    $_->insert(Content => { title => 'Check local' });
  }), 'Transaction');

is($oro->count('Content' => { title => 'Check local' }), 1, 'Count');



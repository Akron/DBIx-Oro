#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Data::Dumper;

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
plan tests => 14;

use_ok 'DBIx::Oro';

# Initialize Oro
my $oro = DBIx::Oro->new(
  %{ $suite->param }
);

ok($oro, 'Handle created');

ok($suite->oro($oro), 'Add to suite');

ok($suite->init(qw/Name Content Book/), 'Init');

END {
  ok($suite->drop, 'Transaction for Dropping') if $suite;
};

# ---

ok($oro->insert(Content => [qw/title content/] =>
	   ['CheckBulk','Das ist der erste content'],
	   ['CheckBulk','Das ist der zweite content'],
	   ['CheckBulk','Das ist der dritte content'],
	   ['CheckBulk','Das ist der vierte content'],
	   ['CheckBulk','Das ist der fünfte content'],
	   ['CheckBulk','Das ist der sechste content'],
	   ['CheckBulk','Das ist der siebte content'],
	   ['CheckBulk','Das ist der achte content'],
	   ['CheckBulk','Das ist der neunte content'],
	   ['CheckBulk','Das ist der zehnte content']), 'Bulk Insert');

ok($oro->txn(
  sub {
    foreach (1..303) {
      $oro->insert(Content => {
	title => 'Single',
	content => 'This is a single content'
      });
    };
  }), 'Insert iteratively.');

# Less than 500
my @massive_bulk;
foreach (1..450) {
  push(@massive_bulk, ['MassiveBulk', 'Content '.$_ ]);
};

ok($oro->insert(Content => [qw/title content/] => @massive_bulk), 'Bulk Insert');

is($oro->count(Content => {title => 'MassiveBulk'}), 450, 'Bulk Check');

# More than 500
@massive_bulk = ();
foreach (1..4500) {
  push(@massive_bulk, ['MassiveBulk', 'Content '.$_ ]);
};

ok($oro->insert(Content => [qw/title content/] => @massive_bulk), 'Bulk Insert 2');

is($oro->count(Content => {title => 'MassiveBulk'}), 4950, 'Bulk Check 2');

is($oro->count('Content'), 5263, 'Count');

is($oro->delete('Content'), 5263, 'Delete all');

is($oro->count('Content'), 0, 'Count');

1;

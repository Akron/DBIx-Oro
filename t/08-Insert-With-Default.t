#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Data::Dumper;
use utf8;
use Math::BigInt;

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
plan tests => 28;

use_ok 'DBIx::Oro';

# Initialize Oro
my $oro = DBIx::Oro->new(
  %{ $suite->param }
);

ok($oro, 'Handle created');

ok($suite->oro($oro), 'Add to suite');

ok($suite->init(qw/Name Book/), 'Init');

END {
  ok($suite->drop, 'Transaction for Dropping') if $suite;
};

# ---

# Insert with default
ok($oro->insert(Name =>
		  ['prename', [surname => 'Meier']] =>
		    map { [$_] } qw/Sabine Peter Michael Frank/ ),
   'Insert with default');

my $meiers = $oro->select('Name');
is((@$meiers), 4, 'Default inserted');
is($meiers->[0]->{surname}, 'Meier', 'Default inserted');
is($meiers->[1]->{surname}, 'Meier', 'Default inserted');
is($meiers->[2]->{surname}, 'Meier', 'Default inserted');
is($meiers->[3]->{surname}, 'Meier', 'Default inserted');

ok($oro->insert(Book =>
		  ['title',
		   [year => 2012],
		   [author_id => 4]
		 ] =>
		   map { [$_] } qw/Misery Carrie It/ ),
   'Insert with default');

my $king = $oro->select('Book');
is((@$king), 3, 'Default inserted');
is($king->[0]->{year}, 2012, 'Default inserted');
ok($king->[0]->{title}, 'Default inserted');
is($king->[1]->{year}, 2012, 'Default inserted');
ok($king->[1]->{title}, 'Default inserted');
is($king->[2]->{year}, 2012, 'Default inserted');
ok($king->[2]->{title}, 'Default inserted');

my $year =  Math::BigInt->new(2012);

# Insert with objects
ok($oro->insert(Book =>
		  ['title',
		   'year',
		   [author_id => 4]
		 ] =>
		   map { [$_, $year] } qw/Misery Carrie It/ ),
   'Insert with default and Object');

$king = $oro->select('Book');
is((@$king), 6, 'Default inserted');
is($king->[0]->{year}, 2012, 'Default inserted');
ok($king->[0]->{title}, 'Default inserted');
is($king->[1]->{year}, 2012, 'Default inserted');
ok($king->[1]->{title}, 'Default inserted');
is($king->[2]->{year}, 2012, 'Default inserted');
ok($king->[2]->{title}, 'Default inserted');

# Insert with objects
ok($oro->insert(Book => {
  title => 'The last stand',
  year => $year,
  author_id => 4
}), 'Insert with Object');


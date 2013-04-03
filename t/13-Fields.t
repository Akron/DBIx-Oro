#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Data::Dumper;
use utf8;

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

ok($suite->init(qw/Name Product Book/), 'Init');

END {
  ok($suite->drop, 'Transaction for Dropping') if $suite;
};

# ---


ok($oro->insert(Name => {
  prename => '  Akron',
  surname => 'Sojolicious'
}), 'Insert');

is($oro->load(Name => ['lower(prename):prename'])->{prename},
	      '  akron', 'Select with lower');

is($oro->load(
  Name => ['ltrim(lower(prename)):prename']
)->{prename},
   'akron', 'Select with lower and ltrim'
);

# Joined table
is($oro->load(
  [
    Name => ['ltrim(lower(prename)):prename'] => {}
  ]
)->{prename}, 'akron', 'Select with lower and ltrim in joined table');

ok($oro->insert(Product => {
  name => 'Book',
  cost => 29.9,
  tax  => 10
}), 'Insert Product');

my $book = $oro->load(
  Product => [
    'name',
    'cost',
    '(cost * (tax / 100)):tax_total'
  ]);

ok($book, 'Book loaded');

# There seems to be a number crunching error in some DBD::SQlite versions I guess.
like($book->{tax_total}, qr{^2\.99}, 'Tax total');


# Test with Prefixes
ok($oro->select([
  Name => ['prename:author'] => { id => 1 },
  Book => ['title','year', 'Name.id'] => { author_id => 1 }
] => { author => 'Fry' } ), 'Prefix 1');

unlike($oro->last_sql, qr{Book\.Name\.id}, 'Prefix 2');



# Todo: Test for 'NOT'

1;

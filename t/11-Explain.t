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
plan tests => 7;

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

ok(length($oro->explain(
  'SELECT
     Name.prename AS "author",
     Book.title AS "title",
     Book.year AS "year"
   FROM
     Name,
     Book
   WHERE
     Name.id = Book.author_id AND
     author_id = ?', [4])) > 0, 'Explain');

no_warn {
  ok(!$oro->update(
    Name =>
      { prename => [qw/user name/], surname => 'xyz777'}
    ), 'Update');
};

#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Data::Dumper;
use utf8;

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
plan tests => 9;

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

# Treatment-Test
my $treat_content = sub {
  return ('content', sub { uc($_[0]) });
};

my $row;

ok($oro->insert(Content => {
  title => 'Not Bulk',
  content => 'Simple Content' }), 'Insert');

ok($row = $oro->load(Content =>
		       ['title', [$treat_content => 'uccont'], 'content'] =>
			 { title => { ne => 'ContentBulk' }}
), 'Load with Treatment');

is($row->{uccont}, 'SIMPLE CONTENT', 'Treatment');

$oro->select(
  Content =>
    ['title', [$treat_content => 'uccont'], 'content'] =>
      { title => { ne => 'ContentBulk' }},
  sub {
    is($_[0]->{uccont}, 'SIMPLE CONTENT', 'Treatment');
  });

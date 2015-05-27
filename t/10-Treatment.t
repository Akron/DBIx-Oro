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
plan tests => 12;

use_ok 'DBIx::Oro';

# Initialize Oro
my $oro = DBIx::Oro->new(
  %{ $suite->param }
);

ok($oro, 'Handle created');

ok($suite->oro($oro), 'Add to suite');

ok($suite->init(qw/Content Name/), 'Init');

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
  content => 'Simple Content',
  author_id => 4
}), 'Insert content');

ok($oro->insert(Name => {
  id => 4,
  prename => 'Hal',
  surname => 'Corben',
  age => 24
}), 'Insert author');

ok($row = $oro->load(Content =>
		       ['title', [$treat_content => 'uccont'], 'content'] =>
			 { title => { ne => 'ContentBulk' }}
), 'Load with Treatment');

is($row->{uccont}, 'SIMPLE CONTENT', 'Treatment');

my $match = $oro->select(
  Content =>
    ['title', [$treat_content => 'uccont'], 'content'] =>
      { title => { ne => 'ContentBulk' }});

is($_->{uccont}, 'SIMPLE CONTENT', 'Treatment') foreach @$match;

# Treatment in join
SKIP: {
  skip "Treatments in joined tables not fixed yet", 2;

  ok($row = $oro->load(
    [
      Content => ['title', [$treat_content => 'uccont'], 'content'] => { author_id => 1 },
      Name => ['prename'] => { id => 1 }
    ] => {
      title => { ne => 'ContentBulk' }
    }
  ), 'Load with Treatment');

  is($row->{uccont}, 'SIMPLE CONTENT', 'Treatment');
};

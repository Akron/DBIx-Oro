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
plan tests => 53;

use_ok 'DBIx::Oro';

# Initialize Oro
my $oro = DBIx::Oro->new(
  %{ $suite->param }
);

ok($oro, 'Handle created');

ok($suite->oro($oro), 'Add to suite');

ok($suite->init(qw/Name Content/), 'Init');

END {
  ok($suite->drop, 'Transaction for Dropping') if $suite;
};

# ---

my @array;
push(@array, ['ContentBulk', $_, $_]) foreach 1..1111;

ok($oro->insert(Content =>
		  [qw/title content author_id/] =>
		    @array), 'Bulk Insert');

is($oro->count('Content'), 1111, 'Count bulk insert');

# Select Operators
my $result = $oro->select(Content => { author_id => [4,5] });
is($result->[0]->{content}, '4', 'Select with array');
is($result->[1]->{content}, '5', 'Select with array');

# lt
$result = $oro->select(Content => { author_id => { lt => 2 } });
is($result->[0]->{content}, '1', 'Select with lt');
is(@$result,1, 'Select with lt');

# <
$result = $oro->select(Content => { author_id => { '<' => 2 } });
is($result->[0]->{content}, '1', 'Select with <');
is(@$result,1, 'Select with <');

# gt
$result = $oro->select(Content => { author_id => { gt => 1110 } });
is($result->[0]->{content}, '1111', 'Select with gt');
is(@$result, 1, 'Select with gt');

# >
$result = $oro->select(Content => { author_id => { '>' => 1110 } });
is($result->[0]->{content}, '1111', 'Select with >');
is(@$result, 1, 'Select with >');

# le
$result = $oro->select(Content => { author_id => { le => 2 } });
is($result->[0]->{content}, '1', 'Select with le');
is($result->[1]->{content}, '2', 'Select with le');
is(@$result,2, 'Select with le');

# <=
$result = $oro->select(Content => { author_id => { '<=' => 2 } });
is($result->[0]->{content}, '1', 'Select with <=');
is($result->[1]->{content}, '2', 'Select with <=');
is(@$result,2, 'Select with <=');

# ge
$result = $oro->select(Content => { author_id => { ge => 1110 } });
is($result->[0]->{content}, '1110', 'Select with ge');
is($result->[1]->{content}, '1111', 'Select with ge');
is(@$result, 2, 'Select with ge');

# >=
$result = $oro->select(Content => { author_id => { '>=' => 1110 } });
is($result->[0]->{content}, '1110', 'Select with >=');
is($result->[1]->{content}, '1111', 'Select with >=');
is(@$result, 2, 'Select with >=');

# ==
$result = $oro->select(Content => { author_id => { '==' => 555 } });
is($result->[0]->{content}, '555', 'Select with ==');
is(@$result, 1, 'Select with ==');

# =
$result = $oro->select(Content => { author_id => { '=' => 555 } });
is($result->[0]->{content}, '555', 'Select with =');
is(@$result, 1, 'Select with =');

# eq
$result = $oro->select(Content => { author_id => { eq => 555 } });
is($result->[0]->{content}, '555', 'Select with eq');
is(@$result, 1, 'Select with eq');

# ne
$result = $oro->select(Content => { author_id => { ne => 1 } });
is(@$result, 1110, 'Select with ne');

# !=
$result = $oro->select(Content => { author_id => { '!=' => 1 } });
is(@$result, 1110, 'Select with !=');

# Between
$result = $oro->select(Content => { author_id => { between => [3,5] } });
is($result->[0]->{content}, '3', 'Select with between');
is($result->[1]->{content}, '4', 'Select with between');
is($result->[2]->{content}, '5', 'Select with between');

# Combining
$result = $oro->select(Content => { author_id => { le => 5, ge => 3 } });
is($result->[0]->{content}, '3', 'Select with combination');
is($result->[1]->{content}, '4', 'Select with combination');
is($result->[2]->{content}, '5', 'Select with combination');

$oro->delete('Name');

ok($oro->insert(Name =>
		  ['prename', [surname => 'Meier']] =>
		    map { [$_] } qw/Sabine Peter Michael Frank/ ),
   'Insert with default');

# Like
$result = $oro->select(Name => { prename => { like => '%e%' } });
is(@$result, 3, 'Select with like');

# Negation like
$result = $oro->select(Name => { prename => { not_like => '%e%' } });
is(@$result, 1, 'Select with not_like');


# Negation Between
$result = $oro->select(Content => { author_id => { not_between => [2, 1110] } });
is($result->[0]->{content}, '1', 'Select with not_between');
is($result->[1]->{content}, '1111', 'Select with not_between');
is(@$result, 2, 'Select with not_between');

# Not element of
$result = $oro->select(Content => { author_id => { le => 6, not => [3,4] }});
is($result->[0]->{content}, '1', 'Select with not in');
is($result->[1]->{content}, '2', 'Select with not in');
is($result->[2]->{content}, '5', 'Select with not in');
is($result->[3]->{content}, '6', 'Select with not in');

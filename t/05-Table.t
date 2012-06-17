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
plan tests => 19;

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



ok($oro->insert(Name => { prename => 'Akron',
			  surname => 'Sojolicious'}), 'Insert');



my ($content, $name);
ok($content = $oro->table('Content'), 'Content');
ok($name = $oro->table('Name'), 'Name');

is($content->insert({ title => 'New Content'}), 1, 'Insert with table');
is($name->insert({
  prename => 'Akron',
  surname => 'Fuxfell'
}),1 , 'Insert with table');

is($name->update({
  surname => 'Sojolicious'
},{
  prename => 'Akron',
}), 2, 'Update with table');

is($name->update({
  surname => 'Sojolicious'
},{
  prename => 'Akron',
}), 2, 'Update with table');

is(@{$name->select({ prename => 'Akron' })}, 2, 'Select with Table');

ok($name->delete({
  id => 1
}), 'Delete with Table');

ok(!$name->load({ id => 1 }), 'Load with Table');

ok($name->merge(
  { prename => 'Akron' },
  { surname => 'Sojolicious' }
), 'Merge with Table');

is($content->insert({ title => 'New Content 2'}), 1, 'Insert with table');
is($content->count, 2, 'Count with Table');

is($content->insert({ title => 'New Content 3'}), 1, 'Insert with table');

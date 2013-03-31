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
  diag 'Database not properly configured';
  exit(0);
};

# Start test
unless ( eval 'use CHI; 1;') {
  diag "No CHI module found";
  pass('CHI not found');
  done_testing;
  exit;
};

use_ok 'DBIx::Oro';

# Initialize Oro
my $oro = DBIx::Oro->new(
  %{ $suite->param }
);

ok($oro, 'Handle created');

ok($suite->oro($oro), 'Add to suite');

ok($suite->init(qw/Name Content Book/), 'Init');

# ---


my $hash = {};

my $chi = CHI->new(
  driver => 'Memory',
  datastore => $hash
);

ok($oro->insert(Name =>
		  ['prename', [surname => 'Meier']] =>
		    map { [$_] } qw/Sabine Peter Michael Frank/ ),
   'Insert with default');


my $result = $oro->select(Name => {
  prename => { like => '%e%' }
});
is(@$result, 3, 'Select with like');
my ($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache');
ok(!(scalar $chi->get_keys), 'No keys');

$result = $oro->select(Name => {
  prename => { like => '%e%' },
  -cache => {
    chi => $chi,
    key => 'Contains e'
  }
});

is(@$result, 3, 'Select with like');
($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache 2');
is(scalar $chi->get_keys, 1, 'One key');

$result = $oro->select(Name => {
  prename => { glob => '*e*' },
  -cache => {
    chi => $chi,
    key => 'Contains e'
  }
});

is(@$result, 3, 'Select with like');
($last_sql, $last_sql_cache) = $oro->last_sql;
ok($last_sql_cache, 'From Cache 1');

is(scalar $chi->get_keys, 1, 'One key');

$result = $oro->select(Name => {
  prename => { glob => '*e*' },
  -cache => {
    chi => $chi,
    key => 'Contains e'
  }
} => sub {
  my $row = shift;
  ok($row->{prename} ~~ [qw/Michael Peter Sabine/], 'Name');
});

($last_sql, $last_sql_cache) = $oro->last_sql;
ok($last_sql_cache, 'From Cache 2');

$result = $oro->select(Name => {
  prename => { like => '%e%' },
  -cache => {
    chi => $chi,
    key => 'Contains e with like'
  }
} => sub {
  my $row = shift;
  ok($row->{prename} ~~ [qw/Michael Peter Sabine/], 'Name 2');
});

($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache 3');

is(scalar $chi->get_keys, 2, 'Two keys');

$result = $oro->select(Name => {
  prename => { like => '%e%' },
  -cache => {
    chi => $chi,
    key => 'Contains e with like'
  }
} => sub {
  my $row = shift;
  ok($row->{prename} ~~ [qw/Michael Peter Sabine/], 'Name 3');
});

($last_sql, $last_sql_cache) = $oro->last_sql;
ok($last_sql_cache, 'From Cache 4');
is(scalar $chi->get_keys, 2, 'One key');

my $count_result = 0;
$result = $oro->select(Name => {
  prename => { like => '%e%' },
  -cache => {
    chi => $chi,
    key => 'Contains e with like'
  }
} => sub {
  my $row = shift;
  ok($row->{prename} ~~ [qw/Michael Peter Sabine/], 'Name 4');
  return $count_result--;
});

($last_sql, $last_sql_cache) = $oro->last_sql;
ok($last_sql_cache, 'From Cache 5');
is(scalar $chi->get_keys, 2, 'Two keys');

$count_result = 1;
$result = $oro->select(Name => {
  -cache => {
    chi => $chi,
    key => 'No restriction'
  }
} => sub {
  my $row = shift;
  return $count_result--;
});

($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache 5');
is(scalar $chi->get_keys, 2, 'Two keys');

$result = $oro->select(Name => {
  -cache => {
    chi => $chi,
    key => 'No restriction'
  }
} => sub { return; });

($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache 6');
is(scalar $chi->get_keys, 3, 'Three keys');

$count_result = 2;
$result = $oro->select(Name => {
  -cache => {
    chi => $chi,
    key => 'No restriction'
  }
} => sub {
  my $row = shift;
  return --$count_result;
});

is($count_result, -1, 'Count Result');
($last_sql, $last_sql_cache) = $oro->last_sql;
ok($last_sql_cache, 'From Cache 6');

is(scalar $chi->get_keys, 3, 'Three keys');

my $load = $oro->load(Name => { prename => 'Sabine' });
delete $load->{id};
is_deeply(
  $load,
  {
    prename => 'Sabine',
    surname => 'Meier',
    age => undef
  },
  'Load');

is(scalar $chi->get_keys, 3, 'Three keys');
($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache 7');

$load = $oro->load(Name => {
  prename => 'Sabine',
  -cache => {
    chi => $chi,
    key => 'load'
  }
});
delete $load->{id};

is_deeply(
  $load,
  {
    prename => 'Sabine',
    surname => 'Meier',
    age => undef
  },
  'Load');

($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache 8');
is(scalar $chi->get_keys, 4, 'Four keys');

$load = $oro->load(Name => {
  prename => 'Sabine',
  -cache => {
    chi => $chi,
    key => 'load'
  }
});
delete $load->{id};

is_deeply(
  $load,
  {
    prename => 'Sabine',
    surname => 'Meier',
    age => undef
  },
  'Load');

($last_sql, $last_sql_cache) = $oro->last_sql;
ok($last_sql_cache, 'From Cache 9');
is(scalar $chi->get_keys, 4, 'Four keys');

is($oro->count('Name'), 4, 'Count');
($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache 10');

is(scalar $chi->get_keys, 4, 'Four keys');

is($oro->count(Name => {
  -cache => {
    chi => $chi,
    key => 'count'
  }
}), 4, 'Count');
($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache 11');
is(scalar $chi->get_keys, 5, 'Five keys');

is($oro->count(Name => {
  -cache => {
    chi => $chi,
    key => 'count'
  }
}), 4, 'Count');

($last_sql, $last_sql_cache) = $oro->last_sql;
ok($last_sql_cache, 'From Cache 7');
is(scalar $chi->get_keys, 5, 'Five keys');

ok($suite->drop, 'Transaction for Dropping') if $suite;

done_testing;

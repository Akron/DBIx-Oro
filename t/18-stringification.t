#!/usr/bin/env perl
package Test::Stringer;
use strict;
use warnings;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

sub new {
  my $class = shift;
  my $string = shift;
  bless \$string, $class;
};

sub to_string {
  my $self = shift;
  '--' . $$self . '--';
};

package main;
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
  done_testing;
};

# ---

ok($oro->insert(
  Name => {
    prename => 'Nils',
    surname => 'Meier'
  }), 'Simple Insert');

ok(my $test = Test::Stringer->new('beispiel'), 'Beispielstring 1');
is("$test", '--beispiel--', 'Beispielstring 2');

ok(my $test2 = Test::Stringer->new('versuch'), 'Beispielstring 3');
is("$test2", '--versuch--', 'Beispielstring 4');

ok($oro->insert(
  Name => {
    prename => 'Michael',
    surname => $test
  }), 'Simple Insert');

is($oro->load(Name => { prename => 'Michael' })->{surname},
   '--beispiel--',
   'Beispielstring 5');

ok($oro->update(
  Name => {
    prename => 'Frank'
  } => {
    surname => $test
  }), 'Simple Insert');

is($oro->load(Name => { surname => '--beispiel--' })->{prename},
   'Frank',
   'Beispielstring 6');

ok($oro->merge(
  Name => {
    prename => 'Johann'
  } => {
    surname => $test
  }), 'Simple Insert');

is($oro->load(Name => { surname => '--beispiel--' })->{prename},
   'Johann',
   'Beispielstring 7');

ok($oro->merge(
  Name => {
    prename => 'Karsten'
  } => {
    surname => $test2
  }), 'Simple Insert');


is($oro->load(Name => { surname => '--versuch--' })->{prename},
   'Karsten',
   'Beispielstring 8');

__END__

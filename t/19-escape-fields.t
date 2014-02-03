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

use_ok 'DBIx::Oro';

# Initialize Oro
my $oro = DBIx::Oro->new(
  %{ $suite->param }
);

ok($oro, 'Handle created');

ok($suite->oro($oro), 'Add to suite');

ok($suite->init(qw/Name Book/), 'Init');

ok($oro->do('Alter Table Name ADD `primary` TEXT'), 'Alter Table');

ok($oro->insert(
  Name => {
    prename => 'Michael',
    surname => 'Schanze',
    primary => 'yeah'
  }), 'Simple Insert');

my $id = $oro->last_insert_id;

ok($oro->update(
  Name => {
    primary => 'yeah2'
  } => {
    id => $id
  }), 'Simple Update');

done_testing;

#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Data::Dumper;
use File::Temp qw/:POSIX/;

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
use_ok 'DBIx::Oro';



# DBIx::Oro::Driver::SQLite
# Create an SQLite Oro object
my $oro = DBIx::Oro->new('file.sqlite');

# Attach new databases
$oro->attach(blog => ':memory:');

# Check, if database was newly created
if ($oro->created) {

  # Create table
  $oro->do(
    'CREATE TABLE Person (
        id    INTEGER PRIMARY KEY,
        name  TEXT NOT NULL,
        age   INTEGER
     )');

  # Create Fulltext Search tables
  $oro->do(
    'CREATE VIRTUAL TABLE Blog USING fts4(title, body)'
  );
};

# Insert values
$oro->insert(Blog => {
  title => 'My Birthday',
  body  => 'It was a wonderful party!'
});

# Create snippet treatment function
my $snippet = $oro->snippet(
  start => '<strong>',
  end   => '</strong>',
  token => 10
);

my $birthday =
  $oro->load(Blog =>
	       [[ $snippet => 'snippet']] => {
		 Blog => { match => 'birthday' }
	       });

is($birthday->{snippet}, 'My <strong>Birthday</strong>', 'String correct');

done_testing;

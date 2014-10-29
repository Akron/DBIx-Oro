#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Data::Dumper;
use File::Temp qw/:POSIX/;

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
my $oro = DBIx::Oro->new('');

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


# Main synopsis

# Create new object
my $oro2 = DBIx::Oro->new(

  # Create an SQLite in-memory DB and initialize
  ':memory:' => sub {

    # Initialize tables with direct SQL
    $_->do(
      'CREATE TABLE User (
         id    INTEGER PRIMARY KEY,
         name  TEXT,
         age   TEXT
      )'
    ) or return -1;
  }
);

# Execute SQL directly
$oro2->do(
  'CREATE TABLE Post (
     time     INTEGER,
     msg      TEXT,
     user_id  INTEGER
  )');

# Wrap multiple actions in a transaction
$oro2->txn(
  sub {

    # Insert a user
    $_->insert(User => {
      name => 'Akron',
      age  => '20'
    }) or return -1;

    # Get latest inserted id
    my $user_id = $_->last_insert_id;

    # Bulk insert messages with default values
    $_->insert(Post => [
      [ time => time ],
      [ user_id => $user_id ],
      'msg'] => (
	['Hello World!'],
	['Seems to work!'],
	['I can insert bulk messages ...'],
	['And I can stop.']
      )
    ) or return -1;
  });

# Load a user based on the name
is($oro2->load(User => { name => 'Akron' })->{age}, 20, 'Age');

# Count the number of entries on a table
is($oro2->count('Post'), 4, 'Postcount');

# Select some messages
my $msgs = $oro2->select(Post => ['msg'] => { msg => { like => '%wo%' } });

foreach (@$msgs) {
  ok($_->{msg}."\n", 'Message');
};
# Hello World!
# Seems to work!

# Create a joined table object
my $join = $oro2->table([
  User => ['name'] => { id => 1 },
  Post => ['msg'] => { user_id => 1 }
]);

# Select on joined tables
my $x = $join->select({ name => 'Akron', msg => { not_glob => 'And*'}, -limit => 2 });
ok($x->[0]->{name}. ': '. $x->[0]->{msg}. "\n", 'Messages');
ok($x->[1]->{name}. ': '. $x->[1]->{msg}. "\n", 'Messages');

# Akron: Hello World!
# Akron: I can insert bulk messages ...

# Debug
my $lsql = $join->last_sql;
like($lsql, qr{User\.name AS `name`}, 'Last SQL 1');
like($lsql, qr{Post\.msg AS `msg`}, 'Last SQL 2');
like($lsql, qr{User\.id = Post\.user_id}, 'Last SQL 3');
like($lsql, qr{Post\.msg NOT GLOB \?}, 'Last SQL 4');
like($lsql, qr{User\.name = \?}, 'Last SQL 5');
like($lsql, qr{LIMIT \?$}, 'Last SQL 6');

done_testing;

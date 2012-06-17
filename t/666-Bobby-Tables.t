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
plan tests => 15;

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

$oro->txn(
  sub {
    my %author;

    $oro->insert(Name => {
      prename => 'Akron',
      surname => 'Fuxfell',
      age => 27
    });
    $author{akron} = $oro->last_insert_id;

    $oro->insert(Name => {
      prename => 'Fry',
      age => 30
    });
    $author{fry} = $oro->last_insert_id;

    $oro->insert(Name => {
      prename => 'Leela',
      age => 24
    });
    $author{leela} = $oro->last_insert_id;

    foreach (qw/Akron Fry Leela/) {
      my $id = $author{lc($_)};
      ok($oro->insert(Book => ['title', 'year', 'author_id'] =>
	  [$_."'s Book 1", 14, $id],
          [$_."'s Book 2", 20, $id],
          [$_."'s Book 3", 19, $id],
          [$_."'s Book 4", 8, $id]), 'Bulk Insertion');
    };
  });

{
  local $SIG{__WARN__} = sub {
    like($_[0], qr/not a valid/, 'Not a valid field')
  };
  ok($oro->select(
    Book => ['count(1) FROM Book; DELETE FROM Book WHERE id != sum(1)']
  ), 'Select with invalid field');

  like($oro->last_sql, qr/^\s*SELECT \* FROM Book\s*$/i, 'Clean sql');
};

{
  local $SIG{__WARN__} = sub {
    like($_[0], qr/not a valid/, 'Not a valid field')
  };

  ok($oro->select(Book => [qw/title year/] => {
    -order => 'year; year'
  }), 'Select with invalid order');


  like($oro->last_sql, qr/^\s*SELECT title, year FROM Book\s*$/i, 'Clean sql');
}


ok($oro->update(
  Name => {
    prename => 'ISALL'
  } => {
    surname => 'Fuxfell'
  }
), 'Update with IS');

__END__


$oro->select(Book => ['year FROM Book; DELETE FROM Book']);

print $oro->last_sql;

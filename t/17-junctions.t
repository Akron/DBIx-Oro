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

$oro->do('Alter Table Name ADD sex TEXT');

END {
  ok($suite->drop, 'Transaction for Dropping') if $suite;
  done_testing;
};

# ---

ok($oro->insert(
  Name =>
    [qw/sex prename surname age/] => (
      [qw/male James Smith 31/],
      [qw/male John Jones 32/],
      [qw/male Robert Taylor 33/],
      [qw/male Michael Brown 34/],
      [qw/male William Williams 35/],
      [qw/male David Wilson 36/],
      [qw/male Richard Johnson 37/],
      [qw/male Charles Davies 38/],
      [qw/male Joseph Robinson 39/],
      [qw/male Thomas Wright 40/],
      [qw/female Mary Thompson 31/],
      [qw/female Patricia Evans 32/],
      [qw/female Linda Walker 33/],
      [qw/female Elizabeth Roberts 35/],
      [qw/female Jennifer Green 36/],
      [qw/female Maria Hall 37/],
      [qw/female Susan Wood 38/],
      [qw/female Margaret Jackson 39/],
      [qw/female Dorothy Clarke 40/]
    )
  ), 'Insert');

ok($oro->insert(Name => {
  sex => 'female',
  prename => 'Barbara',
  surname => 'White'
}), 'Without age');

$oro->txn(
  sub {
    my $oro = shift;
    foreach my $id (1..20) {
      $oro->insert(Book => {
	author_id => $id,
	title => 'My ' . $id . ' book'
      });
    };
  });

my $select = $oro->select(
  Name => {
    sex => 'male',
    age => { gt => 38 },
    -order => 'age'
  }
);

is($select->[0]->{age}, 39, 'Age');
is($select->[0]->{prename}, 'Joseph', 'Prename');
is($select->[0]->{surname}, 'Robinson', 'Surname');
is($select->[1]->{age}, 40, 'Age');
is($select->[1]->{prename}, 'Thomas', 'Prename');
is($select->[1]->{surname}, 'Wright', 'Surname');

$select = $oro->select(
  Name => {
    sex => 'male',
    age => { lt => 33 },
    -order => 'age'
  }
);

is($select->[0]->{age}, 31, 'Age');
is($select->[0]->{prename}, 'James', 'Prename');
is($select->[0]->{surname}, 'Smith', 'Surname');
is($select->[1]->{age}, 32, 'Age');
is($select->[1]->{prename}, 'John', 'Prename');
is($select->[1]->{surname}, 'Jones', 'Surname');

$select = $oro->select(
  Name => {
    sex => 'male',
    -or => [
      { age => { gt => 38 } },
      { age => { lt => 33 } }
    ],
    -order => 'age'
  }
);

like($oro->last_sql, qr!\(age > \? OR age < \?\)!, 'or combination 1');
like($oro->last_sql, qr!sex = \?!, 'or combination 2');

is($select->[0]->{age}, 31, 'Age');
is($select->[0]->{prename}, 'James', 'Prename');
is($select->[0]->{surname}, 'Smith', 'Surname');
is($select->[1]->{age}, 32, 'Age');
is($select->[1]->{prename}, 'John', 'Prename');
is($select->[1]->{surname}, 'Jones', 'Surname');
is($select->[2]->{age}, 39, 'Age');
is($select->[2]->{prename}, 'Joseph', 'Prename');
is($select->[2]->{surname}, 'Robinson', 'Surname');
is($select->[3]->{age}, 40, 'Age');
is($select->[3]->{prename}, 'Thomas', 'Prename');
is($select->[3]->{surname}, 'Wright', 'Surname');

$select = $oro->select(
  Name => {
    -or => [
      {
	sex => 'male',
	age => { gt => 38 }
      },
      {
	sex => 'female',
	age => { lt => 33 }
      }
    ],
    -order => 'age'
  }
);

like($oro->last_sql, qr!\(\(.*?age \> \?.*?\) OR \(.*?sex = \?.*?\)\)!, 'Group or');

is($select->[0]->{age}, 31, 'Age');
is($select->[0]->{prename}, 'Mary', 'Prename');
is($select->[0]->{surname}, 'Thompson', 'Surname');
is($select->[1]->{age}, 32, 'Age');
is($select->[1]->{prename}, 'Patricia', 'Prename');
is($select->[1]->{surname}, 'Evans', 'Surname');
is($select->[2]->{age}, 39, 'Age');
is($select->[2]->{prename}, 'Joseph', 'Prename');
is($select->[2]->{surname}, 'Robinson', 'Surname');
is($select->[3]->{age}, 40, 'Age');
is($select->[3]->{prename}, 'Thomas', 'Prename');
is($select->[3]->{surname}, 'Wright', 'Surname');

$select = $oro->select(
  Name => {
    sex => 'male',
    -or => [
      age => { gt => 38 },
      age => { lt => 33 }
    ],
    -order => 'age'
  }
);

like($oro->last_sql, qr!\(age > \? OR age < \?\)!, 'or combination 1');
like($oro->last_sql, qr!sex = \?!, 'or combination 2');

is($select->[0]->{age}, 31, 'Age');
is($select->[0]->{prename}, 'James', 'Prename');
is($select->[0]->{surname}, 'Smith', 'Surname');
is($select->[1]->{age}, 32, 'Age');
is($select->[1]->{prename}, 'John', 'Prename');
is($select->[1]->{surname}, 'Jones', 'Surname');
is($select->[2]->{age}, 39, 'Age');
is($select->[2]->{prename}, 'Joseph', 'Prename');
is($select->[2]->{surname}, 'Robinson', 'Surname');
is($select->[3]->{age}, 40, 'Age');
is($select->[3]->{prename}, 'Thomas', 'Prename');
is($select->[3]->{surname}, 'Wright', 'Surname');

$select = $oro->select(
  Name => {
    sex => 'male',
    -and => [
      age => { gt => 33 },
      age => { lt => 38 }
    ],
    -order => 'age'
  }
);

is($select->[0]->{age}, 34, 'Age');
is($select->[0]->{prename}, 'Michael', 'Prename');
is($select->[0]->{surname}, 'Brown', 'Surname');
is($select->[1]->{age}, 35, 'Age');
is($select->[1]->{prename}, 'William', 'Prename');
is($select->[1]->{surname}, 'Williams', 'Surname');
is($select->[2]->{age}, 36, 'Age');
is($select->[2]->{prename}, 'David', 'Prename');
is($select->[2]->{surname}, 'Wilson', 'Surname');
is($select->[3]->{age}, 37, 'Age');
is($select->[3]->{prename}, 'Richard', 'Prename');
is($select->[3]->{surname}, 'Johnson', 'Surname');


__END__

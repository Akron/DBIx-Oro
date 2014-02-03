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

my $list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'stArtsWith',
  filterValue => 'J',
  sortBy => 'id',
});

is($list->{filterValue}, 'J', 'Filter Value');
is($list->{startIndex}, 0, 'startIndex');
is($list->{itemsPerPage}, 25, 'itemsperpage');
is($list->{filterOp}, 'startsWith', 'filterOp');
is($list->{totalResults}, 3, 'totalResults');
is($list->{filterBy}, 'surname', 'filterBy');

is($list->{entry}->[0]->{surname}, 'Jackson', 'surname');
is($list->{entry}->[0]->{sex}, 'female', 'sex');
is($list->{entry}->[1]->{prename}, 'John', 'prename');
is($list->{entry}->[1]->{sex}, 'male', 'sex');
is($list->{entry}->[2]->{age}, 37, 'age');
is($list->{entry}->[2]->{sex}, 'male', 'sex');
ok(!$list->{entry}->[3], 'No more entries');

$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'stArtsWith',
  filterValue => 'J',
  sortBy => 'id',
  count => 2
});

is($list->{totalResults}, 3, 'totalResults');
is($list->{itemsPerPage}, 2, 'itemsperpage');
is($list->{entry}->[0]->{surname}, 'Jackson', 'surname');
is($list->{entry}->[1]->{prename}, 'John', 'prename');
ok(!$list->{entry}->[2], 'No third entry');

$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'contains',
  filterValue => 'y',
  sortBy => 'id',
  count => 200
});

is($list->{totalResults}, 1, 'totalResults');
is($list->{itemsPerPage}, 200, 'itemsperpage');
is($list->{entry}->[0]->{surname}, 'Taylor', 'surname');
is($list->{entry}->[0]->{prename}, 'Robert', 'prename');
ok(!$list->{entry}->[1], 'No second entry');

$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'equals',
  filterValue => 'Evans',
  sortBy => 'id',
  count => 200
});

is($list->{totalResults}, 1, 'totalResults');
is($list->{itemsPerPage}, 200, 'itemsperpage');
is($list->{entry}->[0]->{surname}, 'Evans', 'surname');
is($list->{entry}->[0]->{prename}, 'Patricia', 'prename');
ok(!$list->{entry}->[1], 'No second entry');

$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'disparate',
  filterValue => 'Evans',
  sortBy => 'id',
  count => 200
});

is($list->{totalResults}, 19, 'totalResults');
is($list->{itemsPerPage}, 200, 'itemsperpage');

$list = $oro->list('Name' => {
  filterBy => 'age',
  filterOp => 'absent',
  sortBy => 'id',
  count => 1
});

is($list->{totalResults}, 1, 'totalResults');
is($list->{itemsPerPage}, 1, 'itemsperpage');
is($list->{entry}->[0]->{surname}, 'White', 'surname');
is($list->{entry}->[0]->{prename}, 'Barbara', 'prename');
ok(!$list->{entry}->[1], 'No second entry');


$list = $oro->list('Name' => {
  filterBy => 'age',
  filterOp => 'present',
  filterValue => 'Evans', # ignored
  sortBy => 'id',
  count => 1
});

is($list->{totalResults}, 19, 'totalResults');
is($list->{itemsPerPage}, 1, 'itemsperpage');
is($list->{entry}->[0]->{surname}, 'Clarke', 'surname');
is($list->{entry}->[0]->{prename}, 'Dorothy', 'prename');
ok(!$list->{entry}->[1], 'No second entry');

$list = $oro->list('Name' => {
  filterBy => 'age',
  filterOp => 'present',
  filterValue => 'Evans', # ignored
  sortBy => 'id',
  count => 1
});

is($list->{totalResults}, 19, 'totalResults');
is($list->{itemsPerPage}, 1, 'itemsperpage');
is($list->{sortBy}, 'id', 'sort by');
ok(!$list->{sortOrder}, 'sort order');
is($list->{entry}->[0]->{surname}, 'Clarke', 'surname');
is($list->{entry}->[0]->{prename}, 'Dorothy', 'prename');
ok(!$list->{entry}->[1], 'No second entry');


$list = $oro->list('Name' => {
  filterBy => 'age',
  filterOp => 'present',
  filterValue => 'Evans', # ignored
  sortBy => 'age',
  count => 3
});

is($list->{totalResults}, 19, 'totalResults');
is($list->{itemsPerPage}, 3, 'itemsperpage');
is($list->{sortBy}, 'age', 'sort by');
ok(!$list->{sortOrder}, 'sort order');
is($list->{entry}->[0]->{age}, 31, 'age');
is($list->{entry}->[1]->{age}, 31, 'age');
is($list->{entry}->[2]->{age}, 32, 'age');
ok(!$list->{entry}->[3], 'No fourth entry');

$list = $oro->list('Name' => {
  filterBy => 'age',
  filterOp => 'present',
  filterValue => 'Evans', # ignored
  sortBy => 'age',
  sortOrder => 'descending',
  count => 3
});

is($list->{totalResults}, 19, 'totalResults');
is($list->{itemsPerPage}, 3, 'itemsperpage');
is($list->{sortBy}, 'age', 'sort by');
is($list->{filterOp}, 'present', 'filterOp');
ok(!$list->{filterValue}, 'filtervalue');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{entry}->[0]->{age}, 40, 'age');
is($list->{entry}->[1]->{age}, 40, 'age');
is($list->{entry}->[2]->{age}, 39, 'age');
ok(!$list->{entry}->[3], 'No fourth entry');

$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'startsWith',
  filterValue => 'W',
  sortBy => 'surname',
  sortOrder => 'descending',
  count => 2
});

is($list->{totalResults}, 6, 'totalResults');
is($list->{itemsPerPage}, 2, 'itemsperpage');
is($list->{sortBy}, 'surname', 'sort by');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{entry}->[0]->{surname}, 'Wright', 'surname');
is($list->{entry}->[1]->{surname}, 'Wood', 'surname');
ok(!$list->{entry}->[2], 'No third entry');

# startpage 1
$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'startsWith',
  filterValue => 'W',
  sortBy => 'surname',
  sortOrder => 'descending',
  count => 2,
  startPage => 1
});

is($list->{totalResults}, 6, 'totalResults');
is($list->{itemsPerPage}, 2, 'itemsperpage');
is($list->{sortBy}, 'surname', 'sort by');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{entry}->[0]->{surname}, 'Wright', 'surname');
is($list->{entry}->[1]->{surname}, 'Wood', 'surname');
ok(!$list->{entry}->[2], 'No third entry');

# startindex
$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'startsWith',
  filterValue => 'W',
  sortBy => 'surname',
  sortOrder => 'descending',
  startIndex => 1,
  count => 2
});

is($list->{totalResults}, 6, 'totalResults');
is($list->{itemsPerPage}, 2, 'itemsperpage');
is($list->{sortBy}, 'surname', 'sort by');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{entry}->[0]->{surname}, 'Wood', 'surname');
is($list->{entry}->[1]->{surname}, 'Wilson', 'surname');
ok(!$list->{entry}->[2], 'No third entry');

# startpage
$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'STARTSWITH',
  filterValue => 'W',
  sortBy => 'surname',
  sortOrder => 'descending',
  startPage => 2,
  count => 2
});

is($list->{totalResults}, 6, 'totalResults');
is($list->{itemsPerPage}, 2, 'itemsperpage');
is($list->{sortBy}, 'surname', 'sort by');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{entry}->[0]->{surname}, 'Wilson', 'surname');
is($list->{entry}->[1]->{surname}, 'Williams', 'surname');
ok(!$list->{entry}->[2], 'No third entry');

# startIndex and startPage
$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'STARTSWITH',
  filterValue => 'W',
  sortBy => 'surname',
  sortOrder => 'descending',
  startPage => 2,
  startIndex => 1,
  count => 2
});

is($list->{totalResults}, 6, 'totalResults');
is($list->{itemsPerPage}, 2, 'itemsperpage');
is($list->{sortBy}, 'surname', 'sort by');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{entry}->[0]->{surname}, 'Williams', 'surname');
is($list->{entry}->[1]->{surname}, 'White', 'surname');
ok(!$list->{entry}->[2], 'No third entry');

# fields
$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'STARTSWITH',
  filterValue => 'W',
  sortBy => 'surname',
  sortOrder => 'descending',
  fields => [qw/surname age/]
});

is($list->{totalResults}, 6, 'totalResults');
is($list->{itemsPerPage}, 25, 'itemsperpage');
is($list->{sortBy}, 'surname', 'sort by');
is($list->{fields}->[0], 'surname', 'fields');
is($list->{fields}->[1], 'age', 'fields');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{entry}->[0]->{surname}, 'Wright', 'surname');
is($list->{entry}->[0]->{age}, 40, 'age');
is($list->{entry}->[1]->{surname}, 'Wood', 'surname');
is($list->{entry}->[1]->{age}, 38, 'age');
is($list->{entry}->[2]->{surname}, 'Wilson', 'surname');
is($list->{entry}->[2]->{age}, 36, 'age');
is($list->{entry}->[3]->{surname}, 'Williams', 'surname');
is($list->{entry}->[3]->{age}, 35, 'age');
is($list->{entry}->[4]->{surname}, 'White', 'surname');
ok(!$list->{entry}->[4]->{age}, 'age');
is($list->{entry}->[5]->{surname}, 'Walker', 'surname');
is($list->{entry}->[5]->{age}, 33, 'age');
ok(!$list->{entry}->[0]->{prename}, 'No prename');
ok(!$list->{entry}->[0]->{sex}, 'No sex');
ok(!$list->{entry}->[1]->{prename}, 'No prename');
ok(!$list->{entry}->[1]->{sex}, 'No sex');
ok(!$list->{entry}->[2]->{prename}, 'No prename');
ok(!$list->{entry}->[2]->{sex}, 'No sex');
ok(!$list->{entry}->[3]->{prename}, 'No prename');
ok(!$list->{entry}->[3]->{sex}, 'No sex');
ok(!$list->{entry}->[4]->{prename}, 'No prename');
ok(!$list->{entry}->[4]->{sex}, 'No sex');
ok(!$list->{entry}->[5]->{prename}, 'No prename');
ok(!$list->{entry}->[5]->{sex}, 'No sex');


# Comma separated field
$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'STARTSWITH',
  filterValue => 'W',
  sortBy => 'surname',
  sortOrder => 'descending',
  fields => 'surname,age'
});

is($list->{totalResults}, 6, 'totalResults');
is($list->{itemsPerPage}, 25, 'itemsperpage');
is($list->{sortBy}, 'surname', 'sort by');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{fields}->[0], 'surname', 'fields');
is($list->{fields}->[1], 'age', 'fields');
is($list->{entry}->[0]->{surname}, 'Wright', 'surname');
is($list->{entry}->[0]->{age}, 40, 'age');
is($list->{entry}->[1]->{surname}, 'Wood', 'surname');
is($list->{entry}->[1]->{age}, 38, 'age');
is($list->{entry}->[2]->{surname}, 'Wilson', 'surname');
is($list->{entry}->[2]->{age}, 36, 'age');
is($list->{entry}->[3]->{surname}, 'Williams', 'surname');
is($list->{entry}->[3]->{age}, 35, 'age');
is($list->{entry}->[4]->{surname}, 'White', 'surname');
ok(!$list->{entry}->[4]->{age}, 'age');
is($list->{entry}->[5]->{surname}, 'Walker', 'surname');
is($list->{entry}->[5]->{age}, 33, 'age');
ok(!$list->{entry}->[0]->{prename}, 'No prename');
ok(!$list->{entry}->[0]->{sex}, 'No sex');
ok(!$list->{entry}->[1]->{prename}, 'No prename');
ok(!$list->{entry}->[1]->{sex}, 'No sex');
ok(!$list->{entry}->[2]->{prename}, 'No prename');
ok(!$list->{entry}->[2]->{sex}, 'No sex');
ok(!$list->{entry}->[3]->{prename}, 'No prename');
ok(!$list->{entry}->[3]->{sex}, 'No sex');
ok(!$list->{entry}->[4]->{prename}, 'No prename');
ok(!$list->{entry}->[4]->{sex}, 'No sex');
ok(!$list->{entry}->[5]->{prename}, 'No prename');
ok(!$list->{entry}->[5]->{sex}, 'No sex');


# Single field
$list = $oro->list('Name' => {
  filterBy => 'surname',
  filterOp => 'STARTSWITH',
  filterValue => 'W',
  sortBy => 'surname',
  sortOrder => 'descending',
  fields => 'surname'
});

is($list->{totalResults}, 6, 'totalResults');
is($list->{itemsPerPage}, 25, 'itemsperpage');
is($list->{sortBy}, 'surname', 'sort by');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{fields}->[0], 'surname', 'fields');
ok(!$list->{fields}->[1], 'fields');
is($list->{entry}->[0]->{surname}, 'Wright', 'surname');
is($list->{entry}->[1]->{surname}, 'Wood', 'surname');
is($list->{entry}->[2]->{surname}, 'Wilson', 'surname');
is($list->{entry}->[3]->{surname}, 'Williams', 'surname');
is($list->{entry}->[4]->{surname}, 'White', 'surname');
is($list->{entry}->[5]->{surname}, 'Walker', 'surname');
ok(!$list->{entry}->[0]->{prename}, 'No prename');
ok(!$list->{entry}->[0]->{sex}, 'No sex');
ok(!$list->{entry}->[1]->{prename}, 'No prename');
ok(!$list->{entry}->[1]->{sex}, 'No sex');
ok(!$list->{entry}->[2]->{prename}, 'No prename');
ok(!$list->{entry}->[2]->{sex}, 'No sex');
ok(!$list->{entry}->[3]->{prename}, 'No prename');
ok(!$list->{entry}->[3]->{sex}, 'No sex');
ok(!$list->{entry}->[4]->{prename}, 'No prename');
ok(!$list->{entry}->[4]->{sex}, 'No sex');
ok(!$list->{entry}->[5]->{prename}, 'No prename');
ok(!$list->{entry}->[5]->{sex}, 'No sex');
ok(!$list->{entry}->[0]->{age}, 'No age');
ok(!$list->{entry}->[1]->{age}, 'No age');
ok(!$list->{entry}->[2]->{age}, 'No age');
ok(!$list->{entry}->[3]->{age}, 'No age');
ok(!$list->{entry}->[4]->{age}, 'No age');
ok(!$list->{entry}->[5]->{age}, 'No age');

# Joined table
my $table = $oro->table([
  Name => { id => 1 },
  Book => { author_id => 1 }
]);

$list = $table->list({
  filterBy => 'surname',
  filterOp => 'STARTSWITH',
  filterValue => 'W',
  sortBy => 'surname',
  sortOrder => 'descending',
  fields => 'surname,age, sex '
});

is($list->{totalResults}, 6, 'totalResults');
is($list->{itemsPerPage}, 25, 'itemsperpage');
is($list->{sortBy}, 'surname', 'sort by');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{fields}->[0], 'surname', 'fields');
is($list->{fields}->[1], 'age', 'fields');
is($list->{fields}->[2], 'sex', 'fields');
is($list->{entry}->[0]->{surname}, 'Wright', 'surname');
is($list->{entry}->[1]->{surname}, 'Wood', 'surname');
is($list->{entry}->[2]->{surname}, 'Wilson', 'surname');
is($list->{entry}->[3]->{surname}, 'Williams', 'surname');
is($list->{entry}->[4]->{surname}, 'White', 'surname');
is($list->{entry}->[5]->{surname}, 'Walker', 'surname');
ok(!$list->{entry}->[0]->{prename}, 'No prename');
ok(!$list->{entry}->[1]->{prename}, 'No prename');
ok(!$list->{entry}->[2]->{prename}, 'No prename');
ok(!$list->{entry}->[3]->{prename}, 'No prename');
ok(!$list->{entry}->[4]->{prename}, 'No prename');
ok(!$list->{entry}->[5]->{prename}, 'No prename');
is($list->{entry}->[0]->{age}, 40, 'age');
is($list->{entry}->[1]->{age}, 38, 'age');
is($list->{entry}->[2]->{age}, 36, 'age');
is($list->{entry}->[3]->{age}, 35, 'age');
ok(!$list->{entry}->[4]->{age}, 'age');
is($list->{entry}->[5]->{age}, 33, 'age');
is($list->{entry}->[0]->{sex},'male', 'sex');
is($list->{entry}->[1]->{sex},'female', 'sex');
is($list->{entry}->[2]->{sex},'male', 'sex');
is($list->{entry}->[3]->{sex},'male', 'sex');
is($list->{entry}->[4]->{sex},'female', 'sex');
is($list->{entry}->[5]->{sex},'female', 'sex');

$list = $table->list({
  filterBy => 'surname',
  filterOp => 'STARTSWITH',
  filterValue => 'W',
  sortBy => 'surname',
  sortOrder => 'descending',
  fields => 'surname,age, sex '
} => sub {
    my $row = shift;
    my @array;
    foreach (qw/surname age sex/) {
      push(@array, $row->{$_});
    };
    return \@array;
  });

is($list->{totalResults}, 6, 'totalResults');
is($list->{itemsPerPage}, 25, 'itemsperpage');
is($list->{sortBy}, 'surname', 'sort by');
is($list->{sortOrder}, 'descending', 'sort order');
is($list->{fields}->[0], 'surname', 'fields');
is($list->{fields}->[1], 'age', 'fields');
is($list->{fields}->[2], 'sex', 'fields');
is($list->{entry}->[0]->[0], 'Wright', 'surname');
is($list->{entry}->[1]->[0], 'Wood', 'surname');
is($list->{entry}->[2]->[0], 'Wilson', 'surname');
is($list->{entry}->[3]->[0], 'Williams', 'surname');
is($list->{entry}->[4]->[0], 'White', 'surname');
is($list->{entry}->[5]->[0], 'Walker', 'surname');
is($list->{entry}->[0]->[1], 40, 'age');
is($list->{entry}->[1]->[1], 38, 'age');
is($list->{entry}->[2]->[1], 36, 'age');
is($list->{entry}->[3]->[1], 35, 'age');
ok(!$list->{entry}->[4]->[1], 'age');
is($list->{entry}->[5]->[1], 33, 'age');
is($list->{entry}->[0]->[2],'male', 'sex');
is($list->{entry}->[1]->[2],'female', 'sex');
is($list->{entry}->[2]->[2],'male', 'sex');
is($list->{entry}->[3]->[2],'male', 'sex');
is($list->{entry}->[4]->[2],'female', 'sex');
is($list->{entry}->[5]->[2],'female', 'sex');


# Unknown table
no_warn {
  $list = $oro->list('Name2' => {
    filterBy => 'surname',
    filterOp => 'STARTSWITH',
    filterValue => 'W',
    sortBy => 'surname',
    sortOrder => 'descending',
    fields => 'surname,age'
  });

  ok(!$list, 'Unknown table');
};


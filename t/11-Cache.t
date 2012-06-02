use Test::More;
use File::Temp qw/:POSIX/;
use Data::Dumper 'Dumper';
use strict;
use warnings;

if ( eval 'use CHI; 1;') {
  plan tests => 55;
} else {
  plan skip_all => "Not fully implemented yet.";
};

use lib 'lib', '../lib', '../../lib';
use_ok 'DBIx::Oro';

my $_init_name =
'CREATE TABLE Name (
   id       INTEGER PRIMARY KEY,
   prename  TEXT NOT NULL,
   surname  TEXT
 )';

my $_init_content =
'CREATE TABLE Content (
   id         INTEGER PRIMARY KEY,
   content    TEXT,
   title      TEXT,
   author_id  INTEGER
 )';

my $_init_book =
'CREATE TABLE Book (
   id         INTEGER PRIMARY KEY,
   title      TEXT,
   year       INTEGER,
   author_id  INTEGER,
   FOREIGN KEY (author_id) REFERENCES Name(id)
)';


ok(my $oro = DBIx::Oro->new(
  ':memory:' => sub {
    for ($_[0]) {
      $_->do($_init_name);
      $_->do($_init_content);
      $_->do($_init_book);
    };
  }), 'Init real db');


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
  prename => { glob => '*e*' }
});
is(@$result, 3, 'Select with like');
my ($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache');
ok(!(scalar $chi->get_keys), 'No keys');

$result = $oro->select(Name => {
  prename => { glob => '*e*' },
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

is_deeply(
  $oro->load(Name => { prename => 'Sabine' }),
  {id => 4, prename => 'Sabine', surname => 'Meier'},
  'Load');

is(scalar $chi->get_keys, 3, 'Three keys');
($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache 7');

is_deeply(
  $oro->load(Name => {
    prename => 'Sabine',
    -cache => {
      chi => $chi,
      key => 'load'
    }
  }),
  {id => 4, prename => 'Sabine', surname => 'Meier'},
  'Load');

($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'Not from Cache 8');
is(scalar $chi->get_keys, 4, 'Four keys');

is_deeply(
  $oro->load(Name => {
    prename => 'Sabine',
    -cache => {
      chi => $chi,
      key => 'load'
    }
  }),
  {id => 4, prename => 'Sabine', surname => 'Meier'},
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

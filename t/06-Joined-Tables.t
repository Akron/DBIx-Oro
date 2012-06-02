use Test::More;
use strict;
use warnings;
use Data::Dumper;

plan tests => 25;

$|++;

use lib
  'lib',
  '../lib',
  '../../lib';

use_ok 'DBIx::Oro';

my $_init_name =
'CREATE TABLE Name (
   id       INTEGER PRIMARY KEY,
   prename  TEXT NOT NULL,
   surname  TEXT,
   age      INTEGER
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
   id          INTEGER PRIMARY KEY,
   title       TEXT,
   year        INTEGER,
   author_id   INTEGER,
   FOREIGN KEY (author_id)   REFERENCES Name(id)
)';

ok(my $oro = DBIx::Oro->new(
  ':memory:' => sub {
    for ($_[0]) {
      $_->do($_init_name);
      $_->do($_init_content);
      $_->do($_init_book);
    };
  }), 'Init real db');


my %author;

$oro->txn(
  sub {
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
      ok($oro->insert(Content => ['title', 'content', 'author_id'] =>
	  [$_.' 1', 'Content', $id],
          [$_.' 2', 'Content', $id],
          [$_.' 3', 'Content', $id],
          [$_.' 4', 'Content', $id]), 'Bulk Insertion');
    };

    foreach (qw/Akron Fry Leela/) {
      my $id = $author{lc($_)};
      ok($oro->insert(Book => ['title', 'year', 'author_id'] =>
	  [$_."'s Book 1", 14, $id],
          [$_."'s Book 2", 20, $id],
          [$_."'s Book 3", 19, $id],
          [$_."'s Book 4", 8, $id]), 'Bulk Insertion');
    };
  });

my $found = $oro->select([
  Name => ['prename:author'] => { id => 1 },
  Content => ['title'] => { author_id => 1 }
] => { author => 'Fry'} );

is(@$found, 4, 'Joins');

ok($found = $oro->select([
  Name => ['prename:author'] => { id => 1 },
  Book => ['title:title','year:year'] => { author_id => 1 }
] => { author => 'Fry' } ), 'Joins');

my $last_sql = $oro->last_sql;

ok($found = $oro->select([
  Name => ['prename:author'] => { id => 1 },
  Book => ['title','year'] => { author_id => 1 }
] => { author => 'Fry' } ), 'Joins');

is($oro->last_sql, $last_sql, 'Automated aliases');

my $year;
$year += $_->{year} foreach @$found;

is($year, 61, 'Joins');

ok($found = $oro->select([
  Name => { id => 1 },
  Book => ['title:title'] => { author_id => 1 }
] => { prename => 'Fry' } ), 'Joins');

is(@$found, 4, 'Joins');

my $books = $oro->table([
  Name => { id => 1 },
  Book => ['title:title'] => { author_id => 1 }
]);

ok($found = $books->select({ prename => 'Leela'}), 'Joins with table');
is(@$found, 4, 'Joins');

is($books->count({ prename => 'Leela' }), 4, 'Joins with count');
ok($books->load({ prename => 'Leela' })->{title}, 'Joins with load');

ok($oro->do(
  'CREATE TABLE Follower (
     user_id     INTEGER,
     follower_id INTEGER,
     FOREIGN KEY (user_id)     REFERENCES Name(id),
     FOREIGN KEY (follower_id) REFERENCES Name(id)
   )'), 'Create Table');

foreach ([qw/Akron Fry/],
	 [qw/Akron Leela/],
	 [qw/Leela Fry/],
	 [qw/Fry Fry/]) {
  my $id_a = $author{lc($_->[0])};
  my $id_b = $author{lc($_->[1])};
  ok($oro->insert(Follower => {
    user_id     => $id_a,
    follower_id => $id_b
  }), 'Insert ' . $_->[0] );
};

my $select = $oro->select(
  [
    'Name:user' =>
      [qw/prename surname age/] => {
	id => [1,-3]
      },
    'Name:friend' =>
      [qw/prename surname age/] => {
	id => [2,-3],
	-prefix => '*'
      },
    Follower =>
      [] => {
	user_id     => 1,
	follower_id => 2
      }
    ] => {
      'user.prename' => { '!=' => 'Akron' }
    }
);

is_deeply($select->[0], {
  'friend_prename' => 'Fry',
  'friend_age' => 30,
  'age' => 24,
  'prename' => 'Leela',
  'surname' => undef,
  'friend_surname' => undef
}, 'Self join');


__END__

ok($oro->do(
  'ALTER TABLE Book ADD COLUMN coauthor_id INTEGER'
), 'Alter Table');


$oro->select(
  [
    'Name:Author' =>
      [qw/prename surname/] => {
	id => [1, -3]
      },
    'Name:Coauthor' =>
      [qw/prename surname/] => {
	id => [2, -3],
	-prefix => '*'
      },
    'Book' =>
      [qw/title year/] => {
	author_id   => 1,
	coauthor_id => 2
      }
  ]
);

-prefix => '*',
-prefix => 'author'

SELECT
  Author.prename AS prename,
  Author.surname AS surname,
  Coauthor.prename AS coauthor_prename,
  Coauthor.surname AS coauthor_surname,
  Book.title AS title,
  Book.year AS year
FROM
  Name Author,
  Name Coauthor,
  Book
WHERE
  Book.author_id = Author.id AND
  Book.coauthor_id = Coauthor.id AND
  Author.id != Coauthor.id


SELECT
  user.prename AS "user_prename",
  user.surname AS "user_surname",
  user.age AS "user_age",
  friend.prename AS "friend_prename",
  friend.surname AS "friend_surname",
  friend.age AS "friend_age"
FROM
  Name user,
  Name friend,
  Follower
WHERE
  user.id = Follower.user_id AND
  friend.id = Follower.follower_id AND
  user.id != friend.id

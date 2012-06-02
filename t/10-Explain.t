use Test::More;
use File::Temp qw/:POSIX/;
use Data::Dumper 'Dumper';
use strict;
use warnings;

plan tests => 4;


$|++;


use lib 'lib', '../lib', '../../lib';
use_ok 'DBIx::Oro';

my $_init_name =
'CREATE TABLE Name (
   id       INTEGER PRIMARY KEY,
   prename  TEXT NOT NULL,
   surname  TEXT
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
      $_->do($_init_book);
    };
  }), 'Init real db');


ok(length($oro->explain(
  'SELECT
     Name.prename AS "author",
     Book.title AS "title",
     Book.year AS "year"
   FROM
     Name,
     Book
   WHERE
     Name.id = Book.author_id AND
     author_id = ?', [4])) > 0, 'Explain');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->update(
    Name =>
      { prename => [qw/user name/], surname => 'xyz777'}
    ), 'Update');
};

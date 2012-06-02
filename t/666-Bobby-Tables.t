use Test::More;
use File::Temp qw/:POSIX/;
use Data::Dumper 'Dumper';
use strict;
use warnings;

plan tests => 11;


$|++;

use lib 'lib', '../lib', '../../lib';
use_ok 'DBIx::Oro';

my $_init_name =
'CREATE TABLE Name (
   id       INTEGER PRIMARY KEY,
   prename  TEXT NOT NULL,
   surname  TEXT,
   age      INTEGER
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
  }), 'Init memory db');

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

__END__


$oro->select(Book => ['year FROM Book; DELETE FROM Book']);

print $oro->last_sql;

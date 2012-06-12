use Test::More;
use File::Temp qw/:POSIX/;
use Data::Dumper 'Dumper';
use strict;
use warnings;

plan tests => 9;


$|++;


use lib 'lib', '../lib', '../../lib';
use_ok 'DBIx::Oro';

my $oro = DBIx::Oro->new;
$oro->do('CREATE TABLE Name (
   id       INTEGER PRIMARY KEY,
   prename  TEXT NOT NULL,
   surname  TEXT
 )');

ok($oro->insert(Name => {
  prename => 'Akron',
  surname => 'Sojolicious'
}), 'Insert');

is($oro->load(Name => ['lower(prename):prename'])->{prename},
	      'akron', 'Select with lower');

is($oro->load(
  Name => ['ltrim(lower(prename),"a"):prename']
)->{prename},
   'kron', 'Select with lower and ltrim'
);

# Joined table
is($oro->load(
  [
    Name => ['ltrim(lower(prename),"a"):prename'] => {}
  ]
)->{prename}, 'kron', 'Select with lower and ltrim in joined table');


ok($oro->do('CREATE TABLE Product (
   id    INTEGER PRIMARY KEY,
   name  TEXT,
   cost  REAL,
   tax   REAL
 )'), 'Create Table');

ok($oro->insert(Product => {
  name => 'Book',
  cost => 29.9,
  tax  => 10
}), 'Insert Product');

my $book = $oro->load(
  Product => [
    'name',
    'cost',
    '(cost * (tax / 100)):tax_total'
  ]);

ok($book, 'Book loaded');
is($book->{tax_total}, 2.99, 'Tax total');


# Todo: Test for 'NOT'

1;

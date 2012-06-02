use Test::More;
use strict;
use warnings;

plan tests => 16;

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

# Insert with default
ok($oro->insert(Name =>
		  ['prename', [surname => 'Meier']] =>
		    map { [$_] } qw/Sabine Peter Michael Frank/ ),
   'Insert with default');

my $meiers = $oro->select('Name');
is((@$meiers), 4, 'Default inserted');
is($meiers->[0]->{surname}, 'Meier', 'Default inserted');
is($meiers->[1]->{surname}, 'Meier', 'Default inserted');
is($meiers->[2]->{surname}, 'Meier', 'Default inserted');
is($meiers->[3]->{surname}, 'Meier', 'Default inserted');

ok($oro->insert(Book =>
		  ['title',
		   [year => 2012],
		   [author_id => 4]
		 ] =>
		   map { [$_] } qw/Misery Carrie It/ ),
   'Insert with default');

my $king = $oro->select('Book');
is((@$king), 3, 'Default inserted');
is($king->[0]->{year}, 2012, 'Default inserted');
ok($king->[0]->{title}, 'Default inserted');
is($king->[1]->{year}, 2012, 'Default inserted');
ok($king->[1]->{title}, 'Default inserted');
is($king->[2]->{year}, 2012, 'Default inserted');
ok($king->[2]->{title}, 'Default inserted');

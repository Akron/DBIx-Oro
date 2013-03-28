use strict;
use warnings;
use Test::More tests => 30;
use utf8;

$|++;

use lib 'lib', '../lib', '../../lib';
use_ok 'DBIx::Oro';

sub no_warn (&) {
  local $SIG{__WARN__} = sub {};
  $_[0]->();
};


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
   author_id  INTEGER,
   FOREIGN KEY (author_id) REFERENCES Name (id)
 )';

ok(my $oro = DBIx::Oro->new(
  ':memory:' => sub {
    for ($_[0]) {
      $_->do($_init_name);
      $_->do($_init_content);
    };
  }), 'Init memory db');

ok($oro->insert(
  Name => {
    prename => 'Peter',
    surname => 'Meyer'
  }
), 'Insert Author');

ok(my $last_id = $oro->last_insert_id, "Last insert id");

ok($oro->insert(Content => {
  content => 'This is my first novel',
  title => 'Test Suites made simple',
  author_id => $last_id
}), "Insert with foreign key");

ok($oro->merge(Content => {
  content => 'This is my first good novel',
}, {
  title => 'Test Suites made simple',
  author_id => $last_id
}), "Insert with foreign key");

is($oro->count('Content'), 1, 'Count contents');

ok($oro->insert(
  Name => {
    prename => 'Franz',
    surname => 'Jürgens'
  }
), 'Insert Author');

ok($last_id = $oro->last_insert_id, "Last insert id");

ok($oro->merge(Content => {
  content => 'This is my third novel',
}, {
  title => 'I make different novels',
  author_id => $last_id
}), "Insert with foreign key");

is($oro->count('Content'), 2, 'Count contents');

my $select = $oro->select(
  [
    Name => ['prename', 'surname'] => { id => 1 },
    Content => ['title','content'] => { author_id => 1 }
  ] => {
    -order => 'prename'
  }
);

is($select->[0]->{prename}, 'Franz', 'Prename');
is($select->[0]->{surname}, 'Jürgens', 'Surname');
is($select->[0]->{title}, 'I make different novels', 'Surname');
is($select->[0]->{content}, 'This is my third novel', 'Content');


is($select->[1]->{prename}, 'Peter', 'Prename');
is($select->[1]->{surname}, 'Meyer', 'Surname');
is($select->[1]->{title}, 'Test Suites made simple', 'Title');
is($select->[1]->{content}, 'This is my first good novel', 'Content');


# Textual foreign keys

my $_init_session =
'CREATE TABLE Session (
   id TEXT PRIMARY KEY
 )';

my $_init_user =
'CREATE TABLE User (
   id         INTEGER PRIMARY KEY,
   session_id TEXT,
   name       TEXT,
   FOREIGN KEY (session_id) REFERENCES Session (id)
 )';

ok($oro = DBIx::Oro->new(
  ':memory:' => sub {
    for ($_[0]) {
      $_->do($_init_session);
      $_->do($_init_user);
    };
  }), 'Init memory db');

is($oro->count('Session'), 0, 'Session Count');

my $sid = 'abcdefghijklmnopqrstuvwxyzäöüß';

ok(
  $oro->insert(
    Session => {
      id => $sid
    }), 'Session Id'
  );

is($oro->count('Session'), 1, 'Session Count');
is($oro->count('User'), 0, 'User Count');

ok(
  $oro->insert(
    User => {
      name => 'Peter Meyer',
      session_id => $sid
    }), 'User Id'
  );

is($oro->count('User'), 1, 'User Count');

no_warn {
  ok(
    !$oro->insert(
      User => {
	name => 'Testuser',
	session_id => 'xyz'
      }), 'User Id'
    );
};

is($oro->count('User'), 1, 'User Count');

ok($oro->merge(User => {
  name => 'Peter F. Meyer'
}, {
  session_id => $sid
}), 'Merge User');

is($oro->count('User'), 1, 'User Count');

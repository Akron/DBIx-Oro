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

# Start test
plan tests => 34;

use_ok 'DBIx::Oro';

# Initialize Oro
my $oro = DBIx::Oro->new(
  %{ $suite->param }
);

ok($oro, 'Handle created');

ok($suite->oro($oro), 'Add to suite');

ok($suite->init(qw/Name Content Book/), 'Init');

END {
  ok($suite->drop, 'Transaction for Dropping') if $suite;
};

# ---

my ($content, $name);
ok($content = $oro->table('Content'), 'Content');
ok($name = $oro->table('Name'), 'Name');

is($content->insert({ title => 'New Content'}), 1, 'Insert with table');
is($content->insert({ title => 'New Content 2'}), 1, 'Insert with table');
is($content->insert({ title => 'New Content 3'}), 1, 'Insert with table');


is_deeply($content->select(
  ['title'] => {
    -order => '-title',
  }), [
    { title => 'New Content 3' },
    { title => 'New Content 2' },
    { title => 'New Content' }
  ], 'Offset restriction');

# Offset is ignored
no_warn {
  is_deeply($content->select(
    ['title'] => {
      -order => '-title',
      -offset => 5
    }), [
      { title => 'New Content 3' },
      { title => 'New Content 2' },
      { title => 'New Content' }
    ], 'Offset restriction');
};

is_deeply($content->select(
  ['title'] => {
    -order => '-title',
    -limit => 2
  }), [
    { title => 'New Content 3' },
    { title => 'New Content 2' }
  ], 'Limit restriction');

is_deeply($content->select(
  ['title'] => {
    -order => '-title',
    -limit => 2,
    -offset => 1
  }), [
    { title => 'New Content 2' },
    { title => 'New Content' }
  ], 'Order restriction');

ok($content->update({ content => 'abc' } => {title => 'New Content'}), 'Update');;
ok($content->update({ content => 'cde' } => {title => 'New Content 2'}), 'Update');
ok($content->insert({ content => 'cdf',  title => 'New Content 1'}),'Insert');;
ok($content->update({ content => 'efg' } => {title => 'New Content 2'}),'Update');;
ok($content->update({ content => 'efg' } => {title => 'New Content 3'}),'Update');

is(join(',',
	map($_->{id},
	    @{$content->select(
	      ['id'] =>
		{
		  -order => ['-content', '-title']
		}
	      )})), '3,2,4,1', 'Combined Order restriction');

ok($content->insert(
  ['title', 'content'] =>
    ['Bulk 1', 'Content'],
    ['Bulk 2', 'Content'],
    ['Bulk 3', 'Content'],
    ['Bulk 4', 'Content']), 'Bulk Insertion');

# Joins:
ok($oro->delete('Content'), 'Truncate');

my %author;

$oro->txn(
  sub {
    $oro->insert(Name => { prename => 'Akron' });
    $author{akron} = $oro->last_insert_id;

    $oro->insert(Name => { prename => 'Fry' });
    $author{fry} = $oro->last_insert_id;

    $oro->insert(Name => { prename => 'Leela' });
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

# distinct
is(@ { $oro->select('Book' => ['author_id']) }, 12, 'Books');
is(@ { $oro->select('Book' => ['author_id'] => {
  -distinct => 1
})}, 3, 'Distinct Books');

# ok($oro->delete('Name' => { -secure => 1 }), 'Truncate securely');

ok($oro->insert(Book => {
  author_id => $author{ lc 'Akron' },
  title => 'Separated Book',
  year => 1997
}), 'Insert into Book');

is_deeply([ map { $_->{nrs} } @{ $oro->select(
  Book => [
    'count(title):nrs'
  ] => {
    -group => 'author_id'
  })} ], [5, 4, 4], 'Group by');

is_deeply([ map { $_->{nrs} } @{ $oro->select(
  Book => [
    'count(title):nrs'
  ] => {
    -group => ['author_id']
  })} ], [5, 4, 4], 'Group by array');

is_deeply([ map { $_->{nrs} } @{ $oro->select(
  Book => [
    'count(title):nrs'
  ] => {
    -group => ['author_id' => {
      author_id => { ne => 1 }
    }]
  })} ], [4, 4], 'Group by with having');

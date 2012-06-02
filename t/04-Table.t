use Test::More;
use strict;
use warnings;
use utf8;

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

my $_init_content =
'CREATE TABLE Content (
   id         INTEGER PRIMARY KEY,
   content    TEXT,
   title      TEXT,
   author_id  INTEGER
 )';

ok(my $oro = DBIx::Oro->new(
  ':memory:' => sub {
    for ($_[0]) {
      $_->do($_init_name);
      $_->do($_init_content);
    };
  }), 'Init memory db');


ok($oro->insert(Name => { prename => 'Akron',
			  surname => 'Sojolicious'}), 'Insert');



my ($content, $name);
ok($content = $oro->table('Content'), 'Content');
ok($name = $oro->table('Name'), 'Name');

is($content->insert({ title => 'New Content'}), 1, 'Insert with table');
is($name->insert({
  prename => 'Akron',
  surname => 'Fuxfell'
}),1 , 'Insert with table');

is($name->update({
  surname => 'Sojolicious'
},{
  prename => 'Akron',
}), 2, 'Update with table');

is($name->update({
  surname => 'Sojolicious'
},{
  prename => 'Akron',
}), 2, 'Update with table');

is(@{$name->select({ prename => 'Akron' })}, 2, 'Select with Table');

ok($name->delete({
  id => 1
}), 'Delete with Table');

ok(!$name->load({ id => 1 }), 'Load with Table');

ok($name->merge(
  { prename => 'Akron' },
  { surname => 'Sojolicious' }
), 'Merge with Table');

is($content->insert({ title => 'New Content 2'}), 1, 'Insert with table');
is($content->count, 2, 'Count with Table');

is($content->insert({ title => 'New Content 3'}), 1, 'Insert with table');

use Test::More;
use strict;
use warnings;

plan tests => 93;

$|++;

use lib 'lib', '../lib', '../../lib';
use_ok 'DBIx::Oro';

my $_init_content =
'CREATE TABLE Content (
   id       INTEGER PRIMARY KEY,
   content  TEXT
 )';

ok(my $oro = DBIx::Oro->new(
  ':memory:' => sub {
    for ($_[0]) {
      $_->do($_init_content);
    };
  }), 'Init real db');

ok($oro->autocommit(10), 'Set Autocommit');

is($oro->autocommit, 10, 'Autocommit is set');

foreach (1 .. 5) {
  ok($oro->insert(Content => { content => 'Test' }), 'Insert into Content');
};

ok($oro->dbh->rollback, 'Rollback');
is($oro->count('Content'), 0, 'Count Content');
is($oro->delete('Content'), 0, 'Delete table');
ok($oro->autocommit(0), 'Set Autocommit');
ok($oro->autocommit(10), 'Set Autocommit');
is($oro->autocommit, 10, 'Autocommit is set');

foreach (1 .. 9) {
  ok($oro->insert(Content => { content => 'Test' }), 'Insert into Content');
};

ok($oro->dbh->rollback, 'Rollback');
is($oro->count('Content'), 0, 'Count Content');
is($oro->delete('Content'), 0, 'Delete table');
ok($oro->autocommit(0), 'Set Autocommit');
ok($oro->autocommit(10), 'Set Autocommit');
is($oro->autocommit, 10, 'Autocommit is set');



foreach (1 .. 15) {
  ok($oro->insert(Content => { content => 'Test' }), 'Insert into Content');
};

ok($oro->dbh->rollback, 'Rollback');
is($oro->count('Content'), 10, 'Count Content');
is($oro->delete('Content'), 10, 'Delete table');
ok($oro->autocommit(0), 'Set Autocommit');
ok($oro->autocommit(10), 'Set Autocommit');
is($oro->autocommit, 10, 'Autocommit is set');


foreach (1 .. 31) {
  ok($oro->insert(Content => { content => 'Test' }), 'Insert into Content');
};

ok($oro->dbh->rollback, 'Rollback');
is($oro->count('Content'), 30, 'Count Content');
foreach (1 .. 5) {
  ok($oro->insert(Content => { content => 'Test' }), 'Insert into Content');
};
ok($oro->autocommit(0), 'Set Autocommit');
is($oro->count('Content'), 35, 'Count Content');


ok($oro->autocommit(10), 'Set Autocommit');
is($oro->autocommit, 10, 'Autocommit is set');

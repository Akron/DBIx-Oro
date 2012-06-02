use Test::More;
use strict;
use warnings;
use utf8;

plan tests => 10;


$|++;


use lib 'lib', '../lib', '../../lib';
use_ok 'DBIx::Oro';

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
      $_->do($_init_content);
    };
  }), 'Init real db');

ok($oro->insert(Content => [qw/title content/] =>
	   ['CheckBulk','Das ist der erste content'],
	   ['CheckBulk','Das ist der zweite content'],
	   ['CheckBulk','Das ist der dritte content'],
	   ['CheckBulk','Das ist der vierte content'],
	   ['CheckBulk','Das ist der fünfte content'],
	   ['CheckBulk','Das ist der sechste content'],
	   ['CheckBulk','Das ist der siebte content'],
	   ['CheckBulk','Das ist der achte content'],
	   ['CheckBulk','Das ist der neunte content'],
	   ['CheckBulk','Das ist der zehnte content']), 'Bulk Insert');

foreach (1..303) {
  $oro->insert(Content => {
    title => 'Single',
    content => 'This is a single content'
  });
};

# Less than 500
my @massive_bulk;
foreach (1..450) {
  push(@massive_bulk, ['MassiveBulk', 'Content '.$_ ]);
};

ok($oro->insert(Content => [qw/title content/] => @massive_bulk), 'Bulk Insert');

is($oro->count(Content => {title => 'MassiveBulk'}), 450, 'Bulk Check');

# More than 500
@massive_bulk = ();
foreach (1..4500) {
  push(@massive_bulk, ['MassiveBulk', 'Content '.$_ ]);
};

ok($oro->insert(Content => [qw/title content/] => @massive_bulk), 'Bulk Insert 2');

is($oro->count(Content => {title => 'MassiveBulk'}), 4950, 'Bulk Check 2');

is($oro->count('Content'), 5263, 'Count');

is($oro->delete('Content'), 5263, 'Delete all');

is($oro->count('Content'), 0, 'Count');

1;

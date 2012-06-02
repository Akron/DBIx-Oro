use Test::More;
use strict;
use warnings;
use utf8;

plan tests => 6;

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
  }), 'Init memory db');

# Treatment-Test
my $treat_content = sub {
  return ('content', sub { uc($_[0]) });
};

my $row;

ok($oro->insert(Content => {
  title => 'Not Bulk',
  content => 'Simple Content' }), 'Insert');

ok($row = $oro->load(Content =>
		       ['title', [$treat_content => 'uccont'], 'content'] =>
			 { title => { ne => 'ContentBulk' }}
), 'Load with Treatment');

is($row->{uccont}, 'SIMPLE CONTENT', 'Treatment');

$oro->select(Content =>
	       ['title', [$treat_content => 'uccont'], 'content'] =>
		 { title => { ne => 'ContentBulk' }},
	     sub {
	       is($_[0]->{uccont}, 'SIMPLE CONTENT', 'Treatment');
	     });

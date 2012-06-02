use Test::More;
use strict;
use warnings;
use utf8;

plan tests => 52;

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

my @array;
push(@array, ['ContentBulk', $_, $_]) foreach 1..1111;

ok($oro->insert(Content =>
		  [qw/title content author_id/] =>
		    @array), 'Bulk Insert');

is($oro->count('Content'), 1111, 'Count bulk insert');

# Select Operators
my $result = $oro->select(Content => { author_id => [4,5] });
is($result->[0]->{content}, '4', 'Select with array');
is($result->[1]->{content}, '5', 'Select with array');

# lt
$result = $oro->select(Content => { author_id => { lt => 2 } });
is($result->[0]->{content}, '1', 'Select with lt');
is(@$result,1, 'Select with lt');

# <
$result = $oro->select(Content => { author_id => { '<' => 2 } });
is($result->[0]->{content}, '1', 'Select with <');
is(@$result,1, 'Select with <');

# gt
$result = $oro->select(Content => { author_id => { gt => 1110 } });
is($result->[0]->{content}, '1111', 'Select with gt');
is(@$result, 1, 'Select with gt');

# >
$result = $oro->select(Content => { author_id => { '>' => 1110 } });
is($result->[0]->{content}, '1111', 'Select with >');
is(@$result, 1, 'Select with >');

# le
$result = $oro->select(Content => { author_id => { le => 2 } });
is($result->[0]->{content}, '1', 'Select with le');
is($result->[1]->{content}, '2', 'Select with le');
is(@$result,2, 'Select with le');

# <=
$result = $oro->select(Content => { author_id => { '<=' => 2 } });
is($result->[0]->{content}, '1', 'Select with <=');
is($result->[1]->{content}, '2', 'Select with <=');
is(@$result,2, 'Select with <=');

# ge
$result = $oro->select(Content => { author_id => { ge => 1110 } });
is($result->[0]->{content}, '1110', 'Select with ge');
is($result->[1]->{content}, '1111', 'Select with ge');
is(@$result, 2, 'Select with ge');

# >=
$result = $oro->select(Content => { author_id => { '>=' => 1110 } });
is($result->[0]->{content}, '1110', 'Select with >=');
is($result->[1]->{content}, '1111', 'Select with >=');
is(@$result, 2, 'Select with >=');

# ==
$result = $oro->select(Content => { author_id => { '==' => 555 } });
is($result->[0]->{content}, '555', 'Select with ==');
is(@$result, 1, 'Select with ==');

# =
$result = $oro->select(Content => { author_id => { '=' => 555 } });
is($result->[0]->{content}, '555', 'Select with =');
is(@$result, 1, 'Select with =');

# eq
$result = $oro->select(Content => { author_id => { eq => 555 } });
is($result->[0]->{content}, '555', 'Select with eq');
is(@$result, 1, 'Select with eq');

# ne
$result = $oro->select(Content => { author_id => { ne => 1 } });
is(@$result, 1110, 'Select with ne');

# !=
$result = $oro->select(Content => { author_id => { '!=' => 1 } });
is(@$result, 1110, 'Select with !=');

# Between
$result = $oro->select(Content => { author_id => { between => [3,5] } });
is($result->[0]->{content}, '3', 'Select with between');
is($result->[1]->{content}, '4', 'Select with between');
is($result->[2]->{content}, '5', 'Select with between');

# Combining
$result = $oro->select(Content => { author_id => { le => 5, ge => 3 } });
is($result->[0]->{content}, '3', 'Select with combination');
is($result->[1]->{content}, '4', 'Select with combination');
is($result->[2]->{content}, '5', 'Select with combination');

$oro->delete('Name');

ok($oro->insert(Name =>
		  ['prename', [surname => 'Meier']] =>
		    map { [$_] } qw/Sabine Peter Michael Frank/ ),
   'Insert with default');

# Like
$result = $oro->select(Name => { prename => { like => '%e%' } });
is(@$result, 3, 'Select with like');

# Glob
$result = $oro->select(Name => { prename => { glob => '*e*' } });
is(@$result, 3, 'Select with glob');

# Negation like
$result = $oro->select(Name => { prename => { not_like => '%e%' } });
is(@$result, 1, 'Select with not_like');

# Negation Glob
$result = $oro->select(Name => { prename => { not_glob => '*e*' } });
is(@$result, 1, 'Select with not_glob');

# Negation Between
$result = $oro->select(Content => { author_id => { not_between => [2, 1110] } });
is($result->[0]->{content}, '1', 'Select with not_between');
is($result->[1]->{content}, '1111', 'Select with not_between');
is(@$result, 2, 'Select with not_between');

my $surnames = $oro->select('Name');
ok($oro->insert(Name => { prename => 'Daniel' }), 'Insert');
is($oro->load(Name => { surname => undef })->{prename}, 'Daniel', 'Load with undef');
is_deeply($oro->select(Name => { surname => { not => undef } }), $surnames, 'Select with not null');
ok($oro->delete(Name => { prename => 'Daniel'}), 'Delete');

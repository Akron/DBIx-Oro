use Test::More;
use File::Temp qw/:POSIX/;
use Data::Dumper 'Dumper';
use strict;
use warnings;

plan tests => 5;


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

1;

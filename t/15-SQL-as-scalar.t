#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 21;

use Data::Dumper;
use File::Temp qw/:POSIX/;

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

use_ok 'DBIx::Oro';

# Initialize Oro
my $oro = DBIx::Oro->new(
  %{ $suite->param }
);

ok($oro, 'Handle created');

ok($suite->oro($oro), 'Add to suite');

ok($suite->init(qw/Name Content/), 'Init');

END {
  ok($suite->drop, 'Transaction for Dropping') if $suite;
};

ok($oro->insert(Content => { title => 'Check!',
			     content => 'This is content.'}), 'Insert');

ok($oro->insert(Name => { prename => 'Akron',
			  surname => 'Sojolicious'}), 'Insert');

ok($oro->insert(Name => { prename => 'Nils',
			  surname => 'Fragezeichen'}), 'Insert');


$oro->insert(Name => { prename => '0045', surname => 'xyz777'});

is($oro->load(Name => { surname => 'xyz777' })->{prename},
   '0045',
   'Prepended Zeros');

my $string = 'SELECT surname FROM Name WHERE prename = "0045" LIMIT 1';
is($oro->load(Name => { surname => \$string})->{surname}, 'xyz777', 'Subselect');

like($string, qr/$string/, 'SUBSELECT works');

$string = 'SELECT surname FROM Name WHERE prename = ? LIMIT 1';
is($oro->load(Name => {
  surname => [\$string, '0045']
})->{surname}, 'xyz777', 'Subselect');

like($string, qr/\Q$string\E/, 'SUBSELECT works');

ok($oro->insert(Name => {
  surname => 'Meier',
  prename => [\'SELECT prename FROM Name WHERE surname = ?', 'Sojolicious']
}), 'Insert with subselect');

ok(my $user = $oro->load(Name => {surname => 'Meier', prename => 'Akron' }), 'Load user');
is($user->{surname}, 'Meier', 'Surname');
is($user->{prename}, 'Akron', 'Prename');

ok($oro->insert(Name => {
  surname => 'Mueller',
  prename => \'SELECT prename FROM Name WHERE surname = "Fragezeichen"'
}), 'Insert with subselect');

ok($user = $oro->load(Name => {surname => 'Mueller', prename => 'Nils' }), 'Load user');
is($user->{surname}, 'Mueller', 'Surname');
is($user->{prename}, 'Nils', 'Prename');



# Delete all.

#!/usr/bin/env perl
use Test::More;
use File::Temp qw/:POSIX/;
use strict;
use FindBin;
use lib "$FindBin::Bin/../";
use SQLite::Analyzer;
use warnings;
use utf8;

use Data::Dumper;

use_ok 'DBIx::Oro';

my $db_file = ':memory:';

my $oro = DBIx::Oro->new(
  $db_file => sub {
    shift->do(
      "CREATE VIRTUAL TABLE t1 USING ".
	"fts4(content,tokenize=perl 'SQLite::Analyzer::tokenize')"
      );
  });

ok($oro, 'Oro successfully initiated');

my $string = '»Liebe Effi!«';

ok($oro->insert(
  t1 => {
    content => $string
  }
), 'Insert');

print Dumper $oro->load('t1');

ok(my $result = $oro->load(
  t1 =>
    [ [ $oro->offsets => 'offset' ]] =>
      {
	t1 => { match => 'Liebe' }
      }
    ), 'Select with offsets');

my $offset = $result->{offset}->[0];

is('Liebe', bytes::substr($string, $offset->[2],$offset->[3]), 'Equal strings');

done_testing;

__END__


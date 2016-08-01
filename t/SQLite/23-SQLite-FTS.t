#!/usr/bin/env perl
use Test::More;
use File::Temp qw/:POSIX/;
no bytes;
use strict;
use FindBin;
use lib "$FindBin::Bin/../";
use Encode qw/encode decode/;
use SQLite::Analyzer;
use warnings;
use utf8;

# TODO: Check with proper Unicode support!

use_ok 'DBIx::Oro';

my $db_file = ':memory:';

# Do not rely on unicode collation
my $oro = DBIx::Oro->new(
  file => $db_file,
  unicode => 0
);

ok($oro, 'Oro successfully initiated');

SKIP: {
  unless ($oro->dbh->sqlite_register_fts3_perl_tokenizer) {
    my $warn = 'SQLite installed without tokenizer support';
    diag $warn;
    skip $warn, 3;
  };

  $oro->do(
    "CREATE VIRTUAL TABLE t1 USING ".
      "fts4(content,tokenize=perl 'SQLite::Analyzer::tokenize')"
    );

  my @array = (
     [1, '»Liebe Effi!«'],
     [2, '»Ich bin... nun, ich bin für gleich und gleich und natürlich auch für Zärtlichkeit und Liebe. Und wenn es Zärtlichkeit und Liebe nicht sein können, weil Liebe, wie Papa sagt, doch nur ein Papperlapapp ist (was ich aber nicht glaube), nun, dann bin ich für Reichtum und ein vornehmes Haus, ein ganz vornehmes, wo Prinz Friedrich Karl zur Jagd kommt, auf Elchwild oder Auerhahn, oder wo der alte Kaiser vorfährt und für jede Dame, auch für die jungen, ein gnädiges Wort hat. Und wenn wir dann in Berlin sind, dann bin ich für Hofball und Galaoper, immer dicht neben der großen Mittelloge.«'],
     [3, 'Tschüß!'],
     [4, 'Ich sage tschüß und bis zum nächsten Mal']
  );

  ok($oro->insert(
    t1 => ['rowid', 'content'] => (
      @array
    )
  ), 'Insert');

  ok(my $result = $oro->select(
    t1 =>
      ['rowid', [$oro->offsets => 'offset' ]] =>
	{
	  t1 => {
	    match => 'Liebe'
	  },
	  -order_by => 'rowid'
	}
      ), 'Select with offsets');

  my $offset = $result->[0]->{offset}->[0];

  my $text = $array[0]->[1];
  is('iebe ', substr(
    $text,
    $offset->[2],
    $offset->[3]
  ),'Wrong character offsets');

  is('Liebe', bytes::substr(
    $text,
    $offset->[2],
    $offset->[3]
  ),'Equal strings');

  $text = $array[1]->[1];
  $offset = $result->[1]->{offset}->[0];
  is('Liebe', bytes::substr(
    $text,
    $offset->[2],
    $offset->[3]
  ),'Equal strings');

  $offset = $result->[1]->{offset}->[1];
  is('Liebe', bytes::substr(
    $text,
    $offset->[2],
    $offset->[3]
  ),'Equal strings');

  $offset = $result->[1]->{offset}->[2];
  is('Liebe', bytes::substr(
    $text,
    $offset->[2],
    $offset->[3]
  ),'Equal strings');

  ok($result = $oro->select(
    t1 =>
      ['rowid', [$oro->offsets => 'offset' ]] =>
	{
	  t1 => {
	    match => 'tschüß'
	  },
	  -order_by => 'rowid'
	}
      ), 'Select with offsets');

  $offset = $result->[0]->{offset}->[0];
  $text = $array[3]->[1];

  is('tschüß', decode('utf-8',bytes::substr(
    $text,
    $offset->[2],
    $offset->[3]
  )),'Equal strings');

};

done_testing;

__END__


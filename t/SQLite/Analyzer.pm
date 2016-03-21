package SQLite::Analyzer;
use strict;
use warnings;
use utf8;

sub tokenize {
  return sub {
    my $string = shift;
    my $regex      = qr/\p{Word}+(?:[-']\p{Word}+)*/;
    my $term_index = 0;

    return sub { # closure
      $string =~ /$regex/g or return; # either match, or no more token
      my ($start, $end) = ($-[0], $+[0]);
      my $len           = $end-$start;
      my $term          = substr($string, $start, $len);
      return ($term, $len, $start, $end, $term_index++);
    }
  };
};


1;

package SQLite::Analyzer;
use strict;
use warnings;
no bytes;
# use utf8;

sub tokenize {
  return sub {
    my $string = shift;
    # my $regex      = qr/\p{Word}+(?:[-']\p{Word}+)*/;
    my $regex = qr/[a-zA-ZöüäÖÜÄß]+(?:[-'][a-zA-ZöüäÖÜÄß]+)*/;
    my $term_index = 0;

    return sub { # closure
      $string =~ /$regex/g or return; # either match, or no more token

      my ($start, $end) = ($-[0], $+[0]);
      my $len           = $end-$start;
      warn $len . ' vs ' . length($&) if ($len != length($&));
      my $term          = bytes::substr($string, $start, $len);
      return ($term, $len, $start, $end, $term_index++);
    }
  };
};


1;

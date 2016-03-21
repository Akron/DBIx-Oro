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

sub tokenize2 {
  return sub {
    my $string = shift;
    my $regex = qr/\p{Word}+(?:[-']\p{Word}+)*/,
    my $term_index = 0;
    my $end = 0;

    return sub {
      # either match, or no more token
      $string =~ /\G(.*?)($regex)/gc or return;

      my $start = $end + bytes::length($1);

      my $len = bytes::length($2);
      my $term = $2;

#      if ($t =~ /[a-zäöüßÖÜÄ]/i) {
#	$t =~ y/-//ds;
#	return stem_de $t;
 #     };
      # LOWER!!!

      $end = $start + $len;

#warn $term_index . ':' . $term . ':' . $start . '-' . $len;
      return ($term, $len, $start, $end, $term_index++);
    }
  };
}

1;

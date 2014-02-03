package DBTestSuite;
use strict;
use warnings;

our $ft = 'test_db.pl';

our %table;
BEGIN {
  our %table;
  $table{Name} =
    'CREATE TABLE Name (
       id       INTEGER PRIMARY KEY AUTO_INCREMENT,
       prename  TEXT NOT NULL,
       surname  TEXT,
       age      INTEGER
     )';

  $table{Content} =
    'CREATE TABLE Content (
       id         INTEGER PRIMARY KEY AUTO_INCREMENT,
       content    TEXT,
       title      TEXT,
       author_id  INTEGER
     )';

  $table{Book} =
    'CREATE TABLE Book (
       id         INTEGER PRIMARY KEY AUTO_INCREMENT,
       title      TEXT,
       year       INTEGER,
       author_id  INTEGER,
       FOREIGN KEY (author_id)
         REFERENCES Name(id)
     )';

  $table{Follower} =
    'CREATE TABLE Follower (
       user_id     INTEGER,
       follower_id INTEGER,
       FOREIGN KEY (user_id)
         REFERENCES Name(id),
       FOREIGN KEY (follower_id)
         REFERENCES Name(id)
     )';

  $table{Product} =
    'CREATE TABLE Product (
       id    INTEGER PRIMARY KEY,
       name  TEXT,
       cost  REAL,
       tax   REAL
     )';
};

# Import
sub import {
  no strict 'refs';
  no warnings 'redefine';
  my $caller = caller;

  # Don't warn
  *{"${caller}::no_warn"} = sub (&) {
    local $SIG{__WARN__} = sub {};
    $_[0]->();
  };
};

# Constructor
sub new {
  my $class = shift;
  my $self = bless {
    driver => shift
  }, $class;

  # Parse parameters
  $self->{param} = $self->parse_config;
  $self->{param}->{driver} = $self->driver;

  $self->{table} = [];

  # Not sufficient
  if ($self->{driver} eq 'MySQL' &&
	!$self->{param}->{database}) {
    return;
  };

  $self;
};

sub driver {
  $_[0]->{driver};
};

sub param {
  $_[0]->{param};
};

sub oro {
  my $self = shift;
  return $self->{oro} unless @_ > 0;
  $self->{oro} = shift;
  return $self->{oro};
};

# Parse test database configuration file
sub parse_config {
  my $self = shift;
  my $driver = $self->driver;
  my $param;

  my $f;
  if (
    -f ($f = 't/' . $ft) ||
      -f ($f = $ft) ||
	-f ($f = '../t/' . $ft) ||
	  -f ($f = '../../t/' . $ft)
	) {
    if (open (CFG, '<' . $f)) {
      my $cfg = join('', <CFG>);
      close(CFG);
      $param = eval $cfg;
      $param = $param->{$driver} ? $param->{$driver} : undef;
    };
  };

  if ($driver eq 'SQLite' && !$param->{file}) {
    $param->{file} = ':memory:'
  };

  return $param;
};


# Init Databases
sub init {
  my $self = shift;
  my $oro = $self->oro;
  my @tables = @_;

  my @table_init;

  $oro->txn(
    sub {
      foreach my $t (@tables) {
	my $string = $table{$t};

	if ($self->driver eq 'SQLite') {
	  $string =~ s/AUTO_INCREMENT//g;
	};

	$oro->do($string) or return -1;
	push(@table_init, $t);
      };
    }) or return;

  $self->{table} = \@table_init;

  return 1;
};


# Drop tables
sub drop {
  my $self = shift;
  my $oro = $self->oro;

  return unless $oro;

  if ($self->driver eq 'SQLite') {
    $oro->do('PRAGMA foreign_keys = OFF') or return;
  };

  $oro->txn(
    sub {
      foreach my $t (reverse @{$self->{table}}) {
	$oro->do('DROP TABLE ' . $t) or return -1;
      };
    }) or return;
  $self->{table} = [];
  return 1;
};

1;

package DBIx::Oro::Driver::MySQL;
use strict;
use warnings;
use DBIx::Oro;
our @ISA;
BEGIN { @ISA = 'DBIx::Oro' };

use v5.10.1;

use Carp qw/carp croak/;

sub new {
  my $class = shift;
  my %param = @_;

  # Database is not given
  unless ($param{database}) {
    croak 'You have to define a database name';
    return;
  };

  # Bless object with hash
  my $self = bless \%param, $class;

  # Create dsn
  $self->{dsn} = 'DBI:mysql:database=' . $self->{database};

  # Add host and port optionally
  foreach (qw/host port/) {
    $self->{dsn} .= ";$_=" . $self->{$_} if $self->{$_};
  };

  foreach (qw/default_file default_group/) {
    $self->{dsn} .= ";mysql_read_$_=" . $self->{$_} if $self->{$_};
  };

  $self;
};


# Connect to database
sub _connect {
  my $self = shift;

  # Add MySQL specific details
  my $dbh = $self->SUPER::_connect(
    mysql_enable_utf8    => 1,
    mysql_auto_reconnect => 0
  );

  $dbh;
};


# Database driver
sub driver { 'MySQL' };


1;


__END__

=pod

=head1 NAME

DBIx::Oro::Driver::MySQL - MySQL driver for DBIx::Oro


=head1 SYNOPSIS

  use DBIx::Oro;

  my $oro = DBIx::Oro->new(
    driver   => 'MySQL',
    database => 'TestDB',
    user     => 'root',
    password => ''
  );

=head1 DESCRIPTION

L<DBIx::Oro::Driver::MySQL> is a MySQL specific database
driver for L<DBIx::Oro> that provides further functionalities.


=head1 SEE ALSO

The MySQL reference can be found at L<https://dev.mysql.com/doc/>.


=head1 DEPENDENCIES

L<Carp>,
L<DBI>,
L<DBD::MySQL>.


=head1 AVAILABILITY

  https://github.com/Akron/DBIx-Oro


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012-2013, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut

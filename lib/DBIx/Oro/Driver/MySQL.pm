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

  # Create
  my $oro = DBIx::Oro->new(
    driver   => 'MySQL',
    database => 'TestDB',
    user     => 'root',
    password => 's3cr3t'
  );

  $oro->insert(Person => {
    id   => 4,
    name => 'Peter',
    age  => 24
  });


=head1 DESCRIPTION

L<DBIx::Oro::Driver::MySQL> is a MySQL specific database
driver for L<DBIx::Oro> that provides further functionalities.

B<DBIx::Oro::Driver::SQLite is a development release!
Do not rely on any API methods, especially
on those marked as experimental.>


=head1 METHODS

L<DBIx::Oro::Driver::SQLite> inherits all methods from
L<DBIx::Oro> and implements the following new ones
(with possibly overwriting inherited methods).


=head2 new

  my $oro = DBIx::Oro->new(
    driver   => 'MySQL',
    database => 'TestDB',
    user     => 'root',
    password => 's3cr3t'
  );

Creates a new SQLite database accessor object with
C<user> and C<password> information.


=head1 SEE ALSO

The L<MySQL reference|https://dev.mysql.com/doc/>.


=head1 DEPENDENCIES

L<Carp>,
L<DBI>,
L<DBD::MySQL>.


=head1 AVAILABILITY

  https://github.com/Akron/DBIx-Oro


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012-2014, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut

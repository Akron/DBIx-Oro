package DBIx::Oro::Driver::SQLite;
use warnings;
use strict;
use DBIx::Oro;
our @ISA;
BEGIN { @ISA = 'DBIx::Oro' };

use v5.10.1;

# Todo: use 'truncate' for table deletion

# Defaults to 500 for SQLITE_MAX_COMPOUND_SELECT
our $MAX_COMP_SELECT;

BEGIN {
  $MAX_COMP_SELECT = 500;
};

use Carp qw/carp/;

# Find and create database file
use File::Path;
use File::Basename;

# Default arguments for snippet function
my @arguments =
  qw/start end ellipsis column token/;

my $arguments = qr/^(?:start|end|ellipsis|column|token)$/;

my @default = ('<b>', '</b>', '<b>...</b>', -1, -15);


# Constructor
sub new {
  my $class = shift;
  my %param = @_;
  $param{created} //= 0;

  my $autocommit = delete $param{autocommit};

  # Bless object with hash
  my $self = bless \%param, $class;

  # Store filename
  my $file = $self->{file} = $param{file} // '';

  # Temporary or memory file
  if (!$file || $file eq ':memory:') {
    $self->{created} = 1;
  }

  # Create path for file - based on ORLite
  elsif (!-e $file) {

    my $dir = File::Basename::dirname($file);
    unless (-d $dir) {
      File::Path::mkpath( $dir, { verbose => 0 } );
    };

    # Touch the file
    if (open(TOUCH,'>' . $file)) {
      $self->{created} = 1;
      close(TOUCH);
    };
  };

  # Data source name
  $self->{dsn} = 'dbi:SQLite:dbname=' . $self->{file};

  # Attach hash
  $self->{attached} = {};

  # Autocommit
  ${$self->{autocommit}} =
    ${$self->{_autocounter}} = 0;

  # Set autocommit
  $self->autocommit($autocommit) if $autocommit;

  # Return object
  $self;
};


# Initialize database if newly created
sub _init {
  my $self = shift;

  # Get callback
  my $cb = delete $self->{init} if $self->{init} &&
    (ref $self->{init} || '') eq 'CODE';

  # Import SQL file
  my $import    = delete $self->{import};
  my $import_cb = delete $self->{import_cb};

  # Initialize database if newly created
  if ($self->created && ($import || $cb)) {

    # Start creation transaction
    unless (
      $self->txn(
	sub {

	  # Import SQL file
	  if ($import) {
	    $self->import_sql($import, $import_cb) or return -1;
	  };

	  # Release callback
	  if ($cb) {
	    local $_ = $self;
	    return $cb->($self);
	  };
	  return 1;
	})
    ) {

      # Unlink SQLite database
      if (index($self->file, ':') != 0) {
	unlink $self->file;
      };

      # Not successful
      $self = undef;
      return;
    };
  };

  return 1;
};


# Connect to database
sub _connect {
  my $self = shift;
  my $dbh = $self->SUPER::_connect( sqlite_unicode => 1 );

  # Turn foreign keys on as default
  $dbh->do('PRAGMA foreign_keys = ON') unless $self->{foreign_keys};

  # Set busy timeout
  $dbh->sqlite_busy_timeout( $self->{busy_timeout} || 300 );

  # Reattach possibly attached databases
  while (my ($db_name, $file) = each %{$self->{attached}}) {
    $self->prep_and_exec("ATTACH '$file' AS ?", [$db_name]);
  };

  # Return database handle
  $dbh;
};


# File of database
sub file { $_[0]->{file} // '' };


# Database driver
sub driver { 'SQLite' };


# Database was just created
sub created {
  my $self = shift;

  # Creation state is 0
  return 0 unless $self->{created};

  # Check for thread id
  if (defined $self->{tid} && $self->{tid} != threads->tid) {
    return ($self->{created} = 0);
  }

  # Check for process id
  elsif ($self->{pid} != $$) {
    return ($self->{created} = 0);
  };

  # Return creation state
  return 1;
};


# Explain query plan
sub explain {
  my $self = shift;

  # Prepare and execute explain query plan
  my ($rv, $sth) = $self->prep_and_exec(
    'EXPLAIN QUERY PLAN ' . shift, @_
  );

  # Query was not succesfull
  return unless $rv;

  # Create string
  my $string;
  foreach ( @{ $sth->fetchall_arrayref([]) }) {
    $string .= sprintf("%3d | %3d | %3d | %-60s\n", @$_);
  };

  # Return query plan string
  return $string;
};


# Delete with SQLite feature
sub delete {
  my $self = shift;
  my $secure;

  # Check if -secure parameter is set
  if ($_[-1] && ref $_[-1] && ref $_[-1] eq 'HASH') {
    $secure = delete $_[-1]->{-secure} || 0;
  };

  # Delete
  unless ($secure) {

    my $rv = $self->SUPER::delete(@_);

    # Decrement autocommit
    $self->_decr_commit if $rv;

    return $rv;
  }

  # Delete securely
  else {

    # Security value
    my $sec_value;

    # Retrieve secure delete pragma
    my ($rv, $sth) = $self->prep_and_exec('PRAGMA secure_delete');
    $sec_value = $sth->fetchrow_array if $rv;
    $sth->finish;

    # Set secure_delete pragma
    $self->do('PRAGMA secure_delete = ON') unless $sec_value;

    # Delete
    $rv = $self->SUPER::delete(@_);

    # Decrement autocommit
    $self->_decr_commit if $rv;

    # Reset secure_delete pragma
    $self->do('PRAGMA secure_delete = OFF') unless $sec_value;

    # Return value
    return $rv;
  };
};


# Insert values to database
sub insert {
  my $self  = shift;

  # Get table name
  my $table = $self->_table_name(\@_) or return;

  # No parameters
  return unless $_[0];

  # Properties
  my $prop = shift if ref $_[0] eq 'HASH' && ref $_[1];

  # Single insert
  if (ref $_[0] eq 'HASH') {

    # Param
    my %param = %{ shift(@_) };

    # Create insert arrays
    my (@keys, @values);
    while (my ($key, $value) = each %param) {
      # Insert pairs
      next if !ref $key && $key !~ $DBIx::Oro::KEY_REGEX;
      push @keys,   $key;
      push @values, $value;
    };

    # Create insert string
    my $sql = 'INSERT ';

    if ($prop && (my $oc = $prop->{-on_conflict})) {
      if ($oc eq 'replace') {
	$sql = 'REPLACE '
      }
      elsif ($oc eq 'ignore')  {
	$sql .= 'IGNORE '
      };
    };

    $sql .= 'INTO ' . $table .
      ' (' . join(', ', @keys) . ') VALUES (' . DBIx::Oro::_q(\@values) . ')';

    # Prepare and execute
    my $rv = $self->prep_and_exec( $sql, \@values );

    # Decrement autocommit
    $self->_decr_commit if $rv;

    return $rv;
  }

  # Multiple inserts
  elsif (ref($_[0]) eq 'ARRAY') {

    return unless $_[1];

    my @keys = @{ shift(@_) };

    # Default values
    my @default = ();

    # Check if keys are defaults
    my $i = 0;
    my @default_keys;
    while ($keys[$i]) {

      # No default - next
      $i++, next unless ref $keys[$i];

      # Has default value
      my ($key, $value) = @{ splice( @keys, $i, 1) };
      push(@default_keys, $key);
      push(@default, $value);
    };

    # Unshift default keys to front
    unshift(@keys, @default_keys);

    my $sql = 'INSERT INTO ' . $table . ' (' . join(', ', @keys) . ') ';
    my $union = 'SELECT ' . DBIx::Oro::_q(\@keys);

    # Maximum bind variables
    my $max = ($MAX_COMP_SELECT / @keys) - @keys;

    if (scalar @_ <= $max) {

      # Add data unions
      $sql .= $union . ((' UNION ' . $union) x ( scalar(@_) - 1 ));

      # Prepare and execute with prepended defaults
      my @rv = $self->prep_and_exec(
	$sql,
	[ map { (@default, @$_); } @_ ]
      );

      # Decrement autocommit
      $self->_decr_commit if $rv[0];

      return @rv;
    }

    # More than SQLite MAX_COMP_SELECT insertions
    else {

      my ($rv, @v_array);
      my @values = @_;

      # Start transaction
      $self->txn(
	sub {
	  while (@v_array = splice(@values, 0, $max - 1)) {

	    # Delete undef values
	    @v_array = grep($_, @v_array) unless @_;

	    # Add data unions
	    my $sub_sql = $sql . $union .
	      ((' UNION ' . $union) x ( scalar(@v_array) - 1 ));

	    # Prepare and execute
	    my $rv_part = $self->prep_and_exec(
	      $sub_sql,
	      [ map { (@default, @$_); } @v_array ]
	    );

	    # Rollback transaction
	    return -1 unless $rv_part;
	    $rv += $rv_part;
	  };

	}) or return;

      # Decrement autocommit
      $self->_decr_commit if $rv;

      # Everything went fine
      return $rv;
    };
  };

  # Unknown query
  return;
};


# Update existing values in the database
sub update {
  my $self = shift;

  my $rv = $self->SUPER::update(@_);

  # Decrement autocommit
  $self->_decr_commit if $rv;

  return $rv;
};


sub merge {
  my $self = shift;

  my ($rv, $type) = $self->SUPER::merge(@_);

  if ($rv && $type eq 'insert' && ${$self->{autocommit}}) {
    ${$self->{_autocounter}}--;
  };

  return wantarray ? ($rv, $type) : $rv;
};

# Attach database
sub attach {
  my ($self, $db_name, $file) = @_;

  $file //= '';

  # Attach file, memory or temporary database
  my $rv = scalar $self->prep_and_exec("ATTACH '$file' AS ?", [$db_name]);

  $self->{attached}->{$db_name} = $file;
  return $rv;
};


# Detach database
sub detach {
  my $self = shift;
  return unless $_[0];

  # Detach all databases
  foreach my $db_name (@_) {
    delete $self->{attached}->{$db_name};
    return unless $self->prep_and_exec('DETACH ?', [$db_name]);
  };

  return 1;
};


# Wrapper for sqlite last_insert_row_id
sub last_insert_id {
  shift->dbh->sqlite_last_insert_rowid;
};


# Create matchinfo function
sub matchinfo {
  my $self   = shift;

  # Use no multibyte characters
  use bytes;

  # Format string
  my $format = lc(shift) if $_[0] && $_[0] =~ /^[pcnalsx]+$/i;

  # Return anonymous subroutine
  return sub {
    my $column;
    if (@_) {
      $column = shift || 'content';

      # Format string
      $format = lc(shift) if $_[0] && $_[0] =~ /^[pcnalsx]+$/i;
    };

    # Sort format for leading 'pc' if needed
    if ($format) {
      for ($format) {

	# Sort alphabetically
	$_ = join('', sort split('', $_));

	# Delete repeating characters
	s/(.)\1+/$1/g;

	# Prepend 'pc' if necessary
	if (/[xals]/) {
	  tr/pc//d;             # Delete 'pc'
	  $_ = 'pc' . $format;  # Prepend 'pc'
	};
      };
    }

    # No format given
    else {
      $format = 'pcx';
    };

    # Return anonymous subroutine
    return sub {
      return
	'matchinfo(' . $column . ', "' . $format . '")',
	  \&_matchinfo_return,
	    $format;
    };
  };
};


# Treat matchinfo return
sub _matchinfo_return {
  my ($blob, $format) = @_;

  # Get 32-bit blob chunks
  my @matchinfo = unpack('l' . (length($blob) * 4), $blob);

  # Parse format character
  my %match;
  foreach (split '', $format) {

    # Characters: p, c, n
    if ($_ eq 'p' or $_ eq 'c' or $_ eq 'n') {
      $match{$_} = shift @matchinfo;
    }

    # Characters: a, l, s
    elsif ($_ eq 'a' or $_ eq 'l' or $_ eq 's') {
      $match{$_} = [ splice(@matchinfo, 0, $match{c}) ];
    }

    # Characters: x
    elsif ($_ eq 'x') {
      my @match;
      for (1 .. ($match{p} * $match{c})) {
	push(@match, [ splice(@matchinfo, 0, 3) ]);
      };

      $match{$_} = \@match;
    }

    # Unknown character
    else {
      shift @matchinfo;
    };
  };
  return \%match;
};


# Create offsets function
sub offsets {
  my $self = shift;

  # Use no multibyte characters
  use bytes;

  # subroutine
  return sub {
    my $column = shift;
    'offsets(' . ($column || 'content') . ')',
      sub {
	my $blob = shift;
	my @offset;
	my @array = split(/\s/, $blob);
	while (@array) {
	  push(@offset, [ splice(@array, 0, 4) ]);
	};
	return \@offset;
      };
  };
};


# Create snippet function
sub snippet {
  my $self = shift;

  # Snippet parameters
  my @snippet;

  # Parameters are given
  if ($_[0]) {
    my %snippet = ();

    # Parameters are given as a hash
    if ($_[0] =~ $arguments) {
      %snippet = @_;
      foreach (keys %snippet) {
	carp "Unknown snippet parameter '$_'" unless $_ =~ $arguments;
      };
    }

    # Parameters are given as an array
    else {
      @snippet{@arguments} = @_;
    };

    # Trim parameter array and fill gaps with defaults
    my ($s, $i) = (0, 0);
    foreach (reverse @arguments) {
      $s = 1 if defined $snippet{$_};
      unshift(@snippet, $snippet{$_} // $default[$i]) if $s;
      $i++;
    };
  };

  # Return anonymous subroutine
  my $sub = 'sub {
  my $column = $_[0] ? shift : \'content\';
  my $str = "snippet(" . $column ';

  if ($snippet[0]) {
    $sub .= ' . ", ' . join(',', map { '\"' . $_ . '\"' } @snippet) . '"';
  };

  $sub .= " . \")\";\n};";

  return eval( $sub );
};


# New table object
sub table {
  my $self = shift;

  # Get object from superclass
  my $table = $self->SUPER::table(@_);

  # Add autocommit parameters
  foreach (qw/autocommit _autocounter
	     foreign_keys/) {
    $table->{$_} = $self->{$_};
  };

  # Return blessed object
  return $table;
};


# Set foreign_key pragma
sub foreign_keys {
  my $self = shift;

  # Get pragma
  unless (defined $_[0]) {
    return $self->{foreign_keys};
  }

  # Turn foreign keys on
  elsif ($_[0] && !$self->{foreign_keys}) {
    $self->dbh->do('PRAGMA foreign_keys = ON');
    return ($self->{foreign_keys} = 1);
  }

  # Turn foreign keys off
  elsif (!$_[0] && $self->{foreign_keys}) {
    $self->dbh->do('PRAGMA foreign_keys = OFF');
    return ($self->{foreign_keys} = 0);
  };

  return;
};


# Set autocommit
sub autocommit {
  my $self = shift;

  # Get autocommit
  unless (defined $_[0]) {
    return ${$self->{autocommit}} || 0;
  }

  # Set autocommit
  else {
    my $num = shift;
    my $dbh = $self->dbh;

    # Is a number
    if ($num && $num =~ m/^\d+/o) {
      if ($num > 1) {
	$dbh->{AutoCommit} = 0;
	${$self->{autocommit}} = 
	  ${$self->{_autocounter}} = $num;
	return 1;
      }

      else {
	$dbh->{AutoCommit} = 1;
	${$self->{_autocounter}} =
	  ${$self->{autocommit}} = 0;
	return 1;
      };
    }

    # Is null
    elsif (!$num) {
      ${$self->{autocommit}} = 0;
      if (${$self->{_autocounter}}) {
	${$self->{_autocounter}} = 0;
	$dbh->commit;
      };
      $dbh->{AutoCommit} = 1 unless ${$self->{in_txn}};
      return 1;
    }

    # Failure
    else {
      return;
    };
  };
};


# Decrement commit counter
sub _decr_commit {
  my $self = shift;

  # Autocounter is set
  if (${$self->{_autocounter}}) {
    my $auto = --${$self->{_autocounter}};

    # Commit is null
    unless ($auto) {

      $self->dbh->commit unless ${$self->{in_txn}};
      ${$self->{_autocounter}} = ${$self->{autocommit}};
    };
  };
};


1;


__END__

=pod

=head1 NAME

DBIx::Oro::Driver::SQLite - SQLite driver for DBIx::Oro


=head1 SYNOPSIS

  use DBIx::Oro;

  # Create an SQLite Oro object
  my $oro = DBIx::Oro->new('file.sqlite');

  # Attach new databases
  $oro->attach(blog => ':memory:');

  # Check, if database was newly created
  if ($oro->created) {

    # Create table
    $oro->do(
      'CREATE TABLE Person (
          id    INTEGER PRIMARY KEY,
          name  TEXT NOT NULL,
          age   INTEGER
       )');

    # Create Fulltext Search tables
    $oro->do(
      'CREATE VIRTUAL TABLE Blog USING fts4(title, body)'
    );
  };

  # Insert values
  $oro->insert(Blog => {
    title => 'My Birthday',
    body  => 'It was a wonderful party!'
  });

  # Create snippet treatment function
  my $snippet = $oro->snippet(
    start => '<strong>',
    end   => '</strong>',
    token => 10
  );

  my $birthday =
    $oro->load(Blog =>
      [[ $snippet => 'snippet']] => {
        Blog => { match => 'birthday' }
      });

  print $birthday->{snippet};
  # My <strong>Birthday</strong>


=head1 DESCRIPTION

L<DBIx::Oro::Driver::SQLite> is an SQLite specific database
driver for L<DBIx::Oro> that provides further functionalities.

B<DBIx::Oro::Driver::SQLite is a development release!
Do not rely on any API methods, especially
on those marked as experimental.>


=head1 ATTRIBUTES

L<DBIx::Oro::Driver::SQLite> inherits all attributes from
L<DBIx::Oro> and implements the following new ones
(with possibly overwriting inherited attributes).


=head2 created

  if ($oro->created) {
    print "This is brand new!";
  };

If the database was created on construction of the handle,
this attribute is true. Otherwise it's false.
In most cases, this is useful to create tables, triggers
and indices for SQLite databases.

  if ($oro->created) {
    $oro->txn(
      sub {

        # Create table
        $oro->do(
          'CREATE TABLE Person (
              id    INTEGER PRIMARY KEY,
              name  TEXT NOT NULL,
              age   INTEGER
          )'
        ) or return -1;

        # Create index
        $oro->do(
          'CREATE INDEX age_i ON Person (age)'
        ) or return -1;
    });
  };


=head2 file

  my $file = $oro->file;
  $oro->file('myfile.sqlite');

The sqlite file of the database.
This can be a filename (with a path prefix),
C<:memory:> for memory databases or the empty
string for temporary files.


=head2 foreign_keys

  print $oro->foreign_keys;
  $oro->foreign_keys(0);

L<DBIx::Oro::Driver::SQLite> turns foreign keys on by default.
To disable this, set C<foreign_keys> to a false value,
e.g. in the constructor.


=head2 autocommit

  print $oro->autocommit;
  $oro->autocommit(200);

Run commit after a given number of C<insert>, C<update>, C<delete>
or C<merge> operations. Accepts the number of silent operations
till the commit is released. Will automatically commit on start.
To release unstaged changes at the end, just reset autocommit,
e.g. with C<autocommit(0)>.


=head1 METHODS

L<DBIx::Oro::Driver::SQLite> inherits all methods from
L<DBIx::Oro> and implements the following new ones
(with possibly overwriting inherited methods).


=head2 new

  my $oro = DBIx::Oro->new('test.sqlite');
  $oro = DBIx::Oro->new(':memory:');
  $oro = DBIx::Oro->new('');
  $oro = DBIx::Oro->new(
    file   => 'test.sqlite',
    driver => 'SQLite',
    init   => sub {
      shift->do(
        'CREATE TABLE Person (
            id    INTEGER PRIMARY KEY,
            name  TEXT NOT NULL,
            age   INTEGER
         )'
      );
    }
  );

Creates a new SQLite database accessor object on the
given filename or in memory, if the filename is C<:memory:>.
If the database file does not already exist, it is created.
If the file is the empty string, a temporary database
is created. A callback function called C<init> will be triggered,
if the database was newly created. This callback is wrapped inside
a transaction.
The first parameter of the callback function is the Oro object.

See L<new in DBIx::Oro|DBIx::Oro/new> for further information.


=head2 delete

  $oro->delete(Person => { id => 4, -secure => 1});

Deletes rows of a given table, that meet a given condition.
See L<delete in DBIx::Oro|DBIx::Oro/delete> for further information.


=head3 Security

In addition to conditions, the deletion can have further parameters.

=over 2

=item C<-secure>

Forces a secure deletion by overwriting all data with C<0>.

=back

B<The security parameter is EXPERIMENTAL and may change without warnings.>


=head2 attach

  $oro->attach( another_db => 'users.sqlite' );
  $oro->attach( another_db => ':memory:' );
  $oro->attach( 'another_db' );

  $oro->load( 'another_db.user' => { id => 4 } );

Attaches another database file to the connector. All tables of this
database can then be queried with the same connector.

Accepts the database handle name and a database file name.
If the file name is ':memory:' a new database is created in memory.
If no file name is given, a temporary database is created.
If the database file name does not exist, it returns undef.

The database handle can be used as a prefix for tables in queries.
The default prefix for tables of the parent database is C<main.>.

B<This method is EXPERIMENTAL and may change without warnings.>


=head2 detach

  $oro->detach('another_db');
  $oro->detach(@another_dbs);

Detaches attached databases from the connection.

B<This method is EXPERIMENTAL and may change without warnings.>


=head1 TREATMENTS

Treatments can be used for the manipulation of L<select|DBIx::Oro/select>
and L<load|DBIx::Oro/load> queries.

L<DBIx::Oro::Driver::SQLite> implements the following
treatment generators.


=head3 C<matchinfo>

  my $result = $oro->select(
    text =>
      [[ $oro->matchinfo('nls') => 'matchinfo']] => {
        text => { match => 'default transaction' }
      });

  # $result = [{
  #   matchinfo => {
  #     l => [3, 3],
  #     n => 3,
  #     c => 2,
  #     p => 2,
  #     s => [2, 0]
  #   }
  # }, {
  #   matchinfo => {
  #     l => [4, 3],
  #     n => 3,
  #     c => 2,
  #     p => 2,
  #     s => [1, 1]
  #   }
  # }];

Creates a treatment for L<select|DBIx::Oro/select> or L<load|DBIx::Oro/load> that supports
matchinfo information for fts3/fts4 tables.
It accepts a format string containing the characters
C<p>, C<c>, C<n>, C<a>, C<l>, C<s>, and C<x>.
See the L<SQLite manual|https://www.sqlite.org/fts3.html#matchinfo>
for further information on these characters.
The characters C<p> and C<c> will always be set.
Returns the column value as a hash reference of the associated values.


=head3 C<offsets>

  my $result = $oro->load(
    text =>
      [[ $oro->offsets => 'offset' ]] => {
        text => { match => 'world' }
      });

  # $result = {
  #   offset => [
  #     [0, 0, 6, 5],
  #     [1, 0, 24, 5]
  #   ]
  # };

Creates a treatment for L<select|DBIx::Oro/select> or L<load|DBIx::Oro/load> that supports
offset information for fts3/fts4 tables.
It accepts no parameters and returns the column value as an array reference
containing multiple array references.

See the L<SQLite manual|https://www.sqlite.org/fts3.html#section_4_1> for further information.


=head3 C<snippet>

  my $snippet = $oro->snippet(
    start    => '[',
    end      => ']',
    ellipsis => '',
    token    => 5,
    column   => 1
  );

  my $result = $oro->load(
    text =>
      [[ $snippet => 'excerpt' ]] => {
        text => { match => 'cold' }
      });

  print $result->{excerpt};
  # It was [cold] outside

Creates a treatment for L<select|DBIx::Oro/select> or L<load|DBIx::Oro/load> that supports
snippets for fts3/fts4 tables.
On creation it accepts the parameters C<start>, C<end>, C<ellipsis>,
C<token>, and C<column>.

See the L<SQLite manual|https://www.sqlite.org/fts3.html#section_4_2> for further information.


=head1 SEE ALSO

The L<SQLite manual|https://sqlite.org/>,
especially the information regarding the
L<fulltext search extensions|https://sqlite.org/fts3.html>.


=head1 DEPENDENCIES

L<DBI>,
L<DBD::SQLite>.


=head1 AVAILABILITY

  https://github.com/Akron/DBIx-Oro


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2013, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut

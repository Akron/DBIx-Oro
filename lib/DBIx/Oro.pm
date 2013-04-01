package DBIx::Oro;
use strict;
use warnings;

our $VERSION = '0.28_4';

# See the bottom of this file for the POD documentation.

# Todo: Improve documentation
# Todo: -prefix is not documented!
# Todo: Put 'created' in SQLite driver
#       implement ->errstr
#       implement "-with" (?)
# Debug: $lemma_oro->insert({
#          wcl => $_,
#          lemma => $inter
#        },{
#          token => $search_for
#        });
#        (Should raise error)
# Debug: DBIx::Oro-Treatment in Joint Tables
# Deprecate: Delete import_sql method and
#            make it an extension
# Todo: Support left outer join
# Todo: Create all Queries in DBIx::Oro::Query
# Todo: To change queries from different drivers,
#       use events.
# Todo: Return key -column_order => [] with fetchall_arrayref.

use v5.10.1;

use Scalar::Util qw/blessed/;
use Carp qw/carp croak/;
our @CARP_NOT;

# Database connection
use DBI;

our $AS_REGEX = qr/(?::~?[-_a-zA-Z0-9]+)/;

our $OP_REGEX = qr/^(?i:
		     (?:[\<\>\!=]?\=?)|<>|
		     (?:!|not[_ ])?
		     (?:match|like|glob|regex|between)|
		     (?:eq|ne|[gl][te]|not)
		   )$/x;

our $KEY_REGEX = qr/[_\.0-9a-zA-Z]+/;

our $KEY_REGEX_NOPREF = qr/[_0-9a-zA-Z]+/;

our $SFIELD_REGEX =
  qr/(?:$KEY_REGEX|(?:$KEY_REGEX\.)?\*|"[^"]*"|'[^']*')/;

our $FIELD_OP_REGEX = qr/[-\+\/\%\*,]/;

our $FUNCTION_REGEX =
  qr/([_a-zA-Z0-9]*
      \(\s*(?:$SFIELD_REGEX|(?-1))
           (?:\s*$FIELD_OP_REGEX\s*(?:$SFIELD_REGEX|(?-1)))*\s*\))/x;

our $VALID_FIELD_REGEX =
  qr/^(?:$SFIELD_REGEX|$FUNCTION_REGEX)$AS_REGEX?$/;

our $VALID_GROUPORDER_REGEX =
  qr/^[-\+]?(?:$KEY_REGEX|$FUNCTION_REGEX)$/;

our $FIELD_REST_RE = qr/^(.+?)(:~?)([^:"~][^:"]*?)$/;

our $CACHE_COMMENT = 'From Cache';

our @EXTENSIONS = ();


# Import extension
sub import {
  my $class = shift;

  # Load extensions
  foreach (@_) {

    # Load extensions
    my $module = qq{DBIx::Oro::Extension::$_};
    unless (eval "require $module; 1;") {
      croak qq{Unable to load extension "$_"} and return;
    };

    # Push to extension array
    push(@EXTENSIONS, $_);

    # Start import for extensions
    $module->import;
  };
};


# Constructor
sub new {
  my $class = shift;
  my ($self, %param);

  # SQLite - one parameter
  if (@_ == 1) {
    @param{qw/driver file/} = ('SQLite', shift);
  }

  # SQLite - two parameter
  elsif (@_ == 2 && ref $_[1] && ref $_[1] eq 'CODE') {
    @param{qw/driver file init/} = ('SQLite', @_);
  }

  # Hash
  else {
    %param = @_;
  };

  # Init by default
  ${$param{in_txn}} = 0;
  $param{last_sql} = '';

  my $pwd = delete $param{password};

  # Set default to SQLite
  $param{driver} //= 'SQLite';

  # Load driver
  my $package = 'DBIx::Oro::Driver::' . $param{driver};
  unless (eval 'require ' . $package . '; 1;') {
    croak 'Unable to load ' . $package;
    return;
  };

  # On_connect event
  my $on_connect = delete $param{on_connect};

  # Get driver specific handle
  $self = $package->new( %param );

  # No database created
  return unless $self;

  # Connection identifier (for _password)
  $self->{_id} = "$self";

  # Set password securely
  $self->_password($pwd) if $pwd;

  # On connect events
  $self->{on_connect} = {};
  $self->{_connect_cb} = 1;

  if ($on_connect) {
    $self->on_connect(
      ref $on_connect eq 'HASH' ?
      %$on_connect : $on_connect
    ) or return;
  };

  # Connect to database
  $self->_connect or croak 'Unable to connect to database';

  # Savepoint array
  # First element is a counter
  $self->{savepoint} = [1];

  # Initialize database and return Oro instance
  return $self if $self->_init;

  # Fail
  return;
};


# New table object
sub table {
  my $self = shift;

  # Joined table
  my %param = (
    table => do {
      if (ref($_[0])) {
	[ _join_tables( shift(@_) ) ];
      }

      # Table name
      else {
	shift;
      };
    }
  );

  # Clone parameters
  foreach (qw/dbh created in_txn savepoint pid tid
	      dsn _connect_cb on_connect/) {
    $param{$_} = $self->{$_};
  };

  # Connection identifier (for _password)
  $param{_id} = "$self";

  # Bless object with hash
  bless \%param, ref $self;
};


# Database handle
# Based on DBIx::Connector
sub dbh {
  my $self = shift;

  # Store new database handle
  return ($self->{dbh} = shift) if $_[0];

  return $self->{dbh} if ${$self->{in_txn}};

  state $c = 'Unable to connect to database';

  # Check for thread id
  if (defined $self->{tid} && $self->{tid} != threads->tid) {
    return $self->_connect or croak $c;
  }

  # Check for process id
  elsif ($self->{pid} != $$) {
    return $self->_connect or croak $c;
  }

  elsif ($self->{dbh}->{Active}) {
    return $self->{dbh};
  };

  # Return handle if active
  return $self->_connect or croak $c;
};


# Last executed SQL
sub last_sql {
  my $self = shift;
  my $last_sql = $self->{last_sql};

  # Check for recurrent placeholders
  if ($last_sql =~ m/(?:UNION|\?(?:, \?){3,}|(?:\(\?(?:, \?)*\), ){3,})/) {

    our $c;

    # Count Union selects
    state $UNION_RE =
      qr/(?{$c=1})(SELECT \?(?:, \?)*)(?: UNION \1(?{$c++})){3,}/;

    # Count Union selects
    state $BRACKET_RE =
      qr/(?{$c=1})(\(\?(?:, \?)*\))(?:, \1(?{$c++})){3,}/;

    # Count recurring placeholders
    state $PLACEHOLDER_RE =
      qr/(?{$c=1})\?(?:, \?(?{$c++})){3,}/;

    # Rewrite placeholders with count
    for ($last_sql) {
      s/$UNION_RE/WITH $c x UNION $1/og;
      s/$BRACKET_RE/$c x $1/og;
      s/$PLACEHOLDER_RE/$c x ?/og;
    };
  };

  return $last_sql || '' unless wantarray;

  # Return as array
  return ('', 0) unless $last_sql;

  # Check if database request
  state $offset = -1 * length $CACHE_COMMENT;

  return (
    $last_sql,
    substr($last_sql, $offset) eq $CACHE_COMMENT
  );
};


# Database driver
sub driver { '' };


# Extensions
sub extension {
  return @EXTENSIONS;
};


# Insert values to database
# This is the MySQL way
sub insert {
  my $self  = shift;

  # Get table name
  my $table = _table_name($self, \@_) or return;

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
      next unless $key =~ $KEY_REGEX;
      push(@keys, $key);
      push(@values, $value);
    };

    # Create insert string
    my $sql = 'INSERT ';

    if ($prop) {
      given ($prop->{-on_conflict}) {
	when ('replace') { $sql = 'REPLACE '};
	when ('ignore')  { $sql .= 'IGNORE '};
      };
    };

    $sql .= 'INTO ' . $table .
      ' (' . join(', ', @keys) . ') VALUES (' . _q(\@keys) . ')';

    # Prepare and execute
    return scalar $self->prep_and_exec( $sql, \@values );
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

    my $sql .= 'INSERT INTO ' . $table .
      ' (' . join(', ', @keys) . ') ' .
	'VALUES ';

    # Add data in brackets
    $sql .= join(', ', ('(' ._q(\@keys) . ')') x scalar @_ );

    # Prepare and execute with prepended defaults
    return $self->prep_and_exec(
      $sql,
      [ map { (@default, @$_); } @_ ]
    );
  };

  # Unknown query
  return;
};


# Update existing values in the database
sub update {
  my $self  = shift;

  # Get table name
  my $table = _table_name($self, \@_) or return;

  # No parameters
  return unless $_[0];

  # Get pairs
  my ($pairs, $values) = _get_pairs( shift(@_) );

  # Nothing to update
  return unless @$pairs;

  # No arrays or operators allowed
  return unless $pairs ~~ /^$KEY_REGEX\s+(?:=|IS\s)/o;

  # Set undef to pairs
  my @pairs = map { $_ =~ s{ IS NULL$}{ = NULL}io; $_ } @$pairs;

  # Generate sql
  my $sql = 'UPDATE ' . $table . ' SET ' . join(', ', @pairs);

  # Condition
  if ($_[0]) {
    my ($cond_pairs, $cond_values) = _get_pairs( shift(@_) );

    # No conditions given
    if (@$cond_pairs) {

      # Append condition
      $sql .= ' WHERE ' . join(' AND ', @$cond_pairs);

      # Append values
      push(@$values, @$cond_values);
    };
  };

  # Prepare and execute
  my $rv = $self->prep_and_exec($sql, $values);

  # Return value
  return (!$rv || $rv eq '0E0') ? 0 : $rv;
};


# Select from table
sub select {
  my $self  = shift;

  # Get table object
  my ($tables, $fields,
      $join_pairs,
      $treatment,
      $field_alias) = _table_obj($self, \@_);

  my @pairs = @$join_pairs;

  # Fields to select
  if ($_[0] && ref($_[0]) eq 'ARRAY') {

    # Not allowed for join selects
    return if $fields->[0];

    ($fields, $treatment) = _fields($tables->[0], shift(@_) );

    $fields = [ $fields ];
  };

  # Default
  $fields->[0] ||= '*';

  # Create sql query
  my $sql = join(', ', @$fields) . ' FROM ' . join(', ', @$tables);

  # Append condition
  my @values;

  my ($cond, $prep);
  if (($_[0] && ref($_[0]) eq 'HASH') || @$join_pairs) {

    # Condition
    my ($pairs, $values);
    if ($_[0] && ref($_[0]) eq 'HASH') {
      ($pairs, $values, $prep) = _get_pairs( shift(@_), $field_alias);

      push(@values, @$values);

      # Add to pairs
      push(@pairs, @$pairs) if $pairs->[0];
    };

    # Add where clause
    $sql .= ' WHERE ' . join(' AND ', @pairs) if @pairs;

    # Add distinct information
    if ($prep) {
      $sql = 'DISTINCT ' . $sql if delete $prep->{'distinct'};

      # Apply restrictions
      $sql .= _restrictions($prep, \@values);
    };
  };

  my $result;

  # Check cache
  my ($chi, $key, $chi_param);
  if ($prep && $prep->{cache}) {

    # Cache parameters
    ($chi, $key, $chi_param) = @{delete $prep->{cache}};

    # Generate key
    $key = 'SELECT ' . $sql . '-' . join('-', @values) unless $key;

    # Get cache result
    $result = $chi->get($key);
  };

  # Unknown restrictions
  if (scalar keys %$prep) {
    carp 'Unknown restriction option: ' . join(', ', keys %$prep);
  };

  my ($rv, $sth);

  # Result was not cached
  unless ($result) {

    # Prepare and execute
    ($rv, $sth) = $self->prep_and_exec('SELECT ' . $sql, \@values);

    # No statement created
    return unless $sth;
  }

  else {
    # Last sql command
    $self->{last_sql} = 'SELECT ' . $sql . ' -- ' . $CACHE_COMMENT;
  };

  # Prepare treatments
  my (@treatment, %treatsub);
  if ($treatment) {
    @treatment = keys %$treatment;
    foreach (@treatment) {
      $treatsub{$_} = shift(@{$treatment->{$_}});
    };
  };

  # Release callback
  if ($_[0] && ref $_[0] && ref $_[0] eq 'CODE' ) {
    my $cb = shift;

    # Iterate through dbi result
    my ($i, $row) = (0);
    while ($row = $sth ? $sth->fetchrow_hashref : $result->[$i]) {

      # Iterate for cache result
      push(@$result, $row) if $chi && $sth;

      # Increment for cached results
      $i++;

      # Treat result
      if ($treatment) {

	# Treat each treatable row value
	foreach ( grep { exists $row->{$_} } @treatment) {
	  $row->{$_} = $treatsub{$_}->(
	    $row->{$_}, @{ $treatment->{$_} }
	  );
	};
      };

      # Finish if callback returns -1
      local $_ = $row;
      my $rv = $cb->($row);
      if ($rv && $rv eq '-1') {
	$result = undef;
	last;
      };
    };

    # Save to cache
    if ($sth && $chi && $result) {
      $chi->set($key => $result, $chi_param);
    };

    # Came from cache
    return if !$sth && $chi;

    # Finish statement
    $sth->finish;
    return;
  };

  # Create array ref
  unless ($result) {
    $result = $sth->fetchall_arrayref({});

    # Save to stash
    if ($chi && $result) {
      $chi->set($key => $result, $chi_param);
    };
  };

  # Return array ref
  return $result unless $treatment;

  # Treat each row
  foreach my $row (@$result) {

    # Treat each treatable row value
    foreach (@treatment) {
      $row->{$_} = $treatsub{$_}->(
	$row->{$_}, @{$treatment->{$_}}
      ) if $row->{$_};
    };
  };

  # Return result
  $result;
};


# Load one line
sub load {
  my $self  = shift;
  my @param = @_;

  # Has a condition
  if ($param[-1] && ref($param[-1])) {

    # Add limitation to the condition
    if (ref($param[-1]) eq 'HASH') {
      $param[-1]->{-limit} = 1;
    }

    # Load is malformed
    elsif (ref($param[-1]) ne 'ARRAY') {
      carp 'Load is malformed';
      return;
    };
  }

  # Has no condition yet
  else {
    push(@param, { -limit => 1 });
  };

  # Select with limit
  my $row = $self->select(@param);

  # Error or not found
  return unless $row;

  # Return row
  $row->[0];
};


# Delete entry
sub delete {
  my $self  = shift;

  # Get table name
  my $table = _table_name($self, \@_) or return;

  # Build sql
  my $sql = 'DELETE FROM ' . $table;

  # Condition
  my ($pairs, $values, $prep, $secure);
  if ($_[0]) {

    # Add condition
    ($pairs, $values, $prep) = _get_pairs( shift(@_) );

    # Add where clause to sql
    $sql .= ' WHERE ' . join(' AND ', @$pairs) if @$pairs || $prep;

    # Apply restrictions
    $sql .= _restrictions($prep, $values) if $prep;
  };

  # Prepare and execute deletion
  my $rv = $self->prep_and_exec($sql, $values);

  # Return value
  return (!$rv || $rv eq '0E0') ? 0 : $rv;
};


# Update or insert a value
sub merge {
  my $self  = shift;

  # Get table name
  my $table = _table_name($self, \@_) or return;

  my %param = %{ shift( @_ ) };
  my %cond  = $_[0] ? %{ shift( @_ ) } : ();

  # Prefix with table if necessary
  my @param = ( \%param, \%cond );
  unshift(@param, $table) unless $self->{table};

  my $rv;
  my $job = 'update';
  $self->txn(
    sub {

      # Update
      $rv = $self->update( @param );
      return 1 if $rv;

      # Delete all element conditions
      delete $cond{$_} foreach grep( ref( $cond{$_} ), keys %cond);

      # Insert
      @param = ( { %param, %cond } );
      unshift(@param, $table) unless $self->{table};
      $rv = $self->insert(@param) or return -1;

      $job = 'insert';

      return;
    }) or return;

  # Return value is bigger than 0
  if ($rv && $rv > 0) {
    return wantarray ? ($rv, $job) : $rv;
  };

  return;
};


# Count results
sub count {
  my $self  = shift;

  # Init arrays
  my ($tables, $fields, $join_pairs, $treatment, $field_alias) =
    _table_obj($self, \@_);

  my @pairs = @$join_pairs;

  # Build sql
  my $sql =
    'SELECT ' . join(', ', 'count(1)', @$fields) .
      ' FROM '  . join(', ', @$tables);

  # Ignore fields
  shift if $_[0] && ref $_[0] eq 'ARRAY';

  # Get conditions
  my ($pairs, $values, $prep);
  if ($_[0] && ref $_[0] eq 'HASH') {
    ($pairs, $values, $prep) = _get_pairs( shift(@_), $field_alias );
    push(@pairs, @$pairs) if $pairs->[0];
  };

  # Add where clause
  $sql .= ' WHERE ' . join(' AND ', @pairs) if @pairs;
  $sql .= ' LIMIT 1';

  my $result;

  # Check cache
  my ($chi, $key, $chi_param);
  if ($prep && $prep->{cache}) {

    # Cache parameters
    ($chi, $key, $chi_param) = @{$prep->{cache}};

    # Generate key
    $key = $sql . '-' . join('-', @$values) unless $key;

    # Get cache result
    if ($result = $chi->get($key)) {

      # Last sql command
      $self->{last_sql} = $sql . ' -- ' . $CACHE_COMMENT;

      # Return cache result
      return $result;
    };
  };

  # Prepare and execute
  my ($rv, $sth) = $self->prep_and_exec($sql, $values || []);

  # Return value is empty
  return 0 if !$rv;

  # Return count
  $result = $sth->fetchrow_arrayref->[0] || 0;
  $sth->finish;

  # Save to cache
  $chi->set($key => $result, $chi_param) if $chi && $result;

  # Return result
  $result;
};


# Prepare and execute
sub prep_and_exec {
  my ($self, $sql, $values, $cached) = @_;
  my $dbh = $self->dbh;

  # Last sql command
  $self->{last_sql} = $sql;

  # Prepare
  my $sth =
    $cached ? $dbh->prepare_cached( $sql ) :
      $dbh->prepare( $sql );

  # Check for errors
  if ($dbh->err) {

    if (index($dbh->errstr, 'database') <= 0) {
      carp $dbh->errstr . ' in "' . $self->last_sql . '"';
      return;
    };

    # Retry with reconnect
    $dbh = $self->_connect;

    $sth =
      $cached ? $dbh->prepare_cached( $sql ) :
	$dbh->prepare( $sql );

    if ($dbh->err) {
      carp $dbh->errstr . ' in "' . $self->last_sql . '"';
      return;
    };
  };

  # No statement handle established
  return unless $sth;

  # Execute
  my $rv = $sth->execute( @$values );

  # Check for errors
  if ($dbh->err) {
    carp $dbh->errstr . ' in "' . $self->last_sql . '"';
    return;
  };

  # Return value and statement
  return ($rv, $sth) if wantarray;

  # Finish statement
  $sth->finish;

  # Return value
  $rv;
};


# Wrapper for DBI do
sub do {
  $_[0]->{last_sql} = $_[1];

  # Database connection
  my $dbh = shift->dbh;

  my $rv = $dbh->do( @_ );

  # Error
  carp $dbh->errstr . ' in "' . $_[0] . '"' if !$rv && $dbh->err;
  return $rv;
};


# Explain query plan
sub explain {
  'Not implemented for ' . $_[0]->driver;
};


# Wrap a transaction
sub txn {
  my $self = shift;

  # No callback defined
  return unless $_[0] && ref($_[0]) eq 'CODE';

  my $dbh = $self->dbh;

  # Outside transaction
  if ($dbh->{AutoCommit}) {

    # Start new transaction
    $dbh->begin_work;

    ${$self->{in_txn}} = 1;

    # start
    local $_ = $self;
    my $rv = $_[0]->($self);
    if (!$rv || $rv ne '-1') {
      ${$self->{in_txn}} = 0;
      $dbh->commit;
      return 1;
    };

    # Rollback
    ${$self->{in_txn}} = 0;
    $dbh->rollback;
    return;
  }

  # Inside transaction
  else {
    ${$self->{in_txn}} = 1;

    # Push savepoint on stack
    my $sp_array = $self->{savepoint};

    # Use PID for concurrent accesses
    my $sp = "orosp_${$}_";

    # Use TID for concurrent accesses
    $sp .= threads->tid . '_' if $self->{tid};

    $sp .= $sp_array->[0]++;

    # Push new savepoint to array
    push(@$sp_array, $sp);

    # Start transaction
    $self->do("SAVEPOINT $sp");

    # Run wrap actions
    my $rv = $_[0]->($self);

    # Pop savepoint from stack
    my $last_sp = pop(@$sp_array);
    if ($last_sp eq $sp) {
      $sp_array->[0]--;
    }

    # Last savepoint does not match
    else {
      carp "Savepoint $sp is not the last savepoint on stack";
    };

    # Commit savepoint
    if (!$rv || $rv ne '-1') {
      $self->do("RELEASE SAVEPOINT $sp");
      return 1;
    };

    # Rollback
    $self->do("ROLLBACK TO SAVEPOINT $sp");
    return;
  };
};


# Add connect event
sub on_connect {
  my $self = shift;
  my $cb   = pop;

  # Parameter is no subroutine
  return unless ref $cb && ref $cb eq 'CODE';

  my $name = shift || '_cb_' . $self->{_connect_cb}++;

  # Push subroutines on_connect
  unless (exists $self->{on_connect}->{$name}) {
    $self->{on_connect}->{$name} = $cb;
    return 1;
  };

  # Event was not newly established
  return;
};


# Wrapper for DBI last_insert_id
sub last_insert_id {
  my $dbh = shift->dbh;
  @_ = (undef) x 4 unless @_;
  $dbh->last_insert_id(@_);
};


# Import files
sub import_sql {
  my $self = shift;

  carp 'import_sql is deprecated and will be deleted in further versions';

  # Get callback
  my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

  my $files = @_ > 1 ? \@_ : shift;

  return unless $files;

  # Import subroutine
  my $import = sub {
    my $file = shift;

    # No file given
    return unless $file;

    if (open(SQL, '<:utf8', $file)) {
      my @sql = split(/^--\s-.*?$/m, join('', <SQL>));
      close(SQL);

      # Start transaction
      return $self->txn(
	sub {
	  my ($sql, @sql_seq);;
	  foreach $sql (@sql) {
	    $sql =~ s/^(?:--.*?|\s*)?$//mg;
	    $sql =~ s/\n\n+/\n/sg;

	    # Use callback
	    @sql_seq = $cb->($sql) if $cb && $sql;

	    next unless $sql;

	    # Start import
	    foreach (@sql_seq) {
	      $self->do($_) or return -1;
	    };
	  };
	}
      );
    }

    # Unable to read SQL file
    else {
      carp "Unable to import file '$file'";
      return;
    };
  };

  # Multiple file import
  if (ref $files) {
    return $self->txn(
      sub {
	foreach (@$files) {
	  $import->($_) or return -1;
	};
      });
  };

  # Single file import
  return $import->($files);
};


# Disconnect on destroy
sub DESTROY {
  my $self = shift;

  # Check if table is parent
  unless (exists $self->{table}) {

    # No database connection
    return $self unless $self->{dbh};

    # Delete password
    $self->_password(0);

    # Delete cached kids
    my $kids = $self->{dbh}->{CachedKids};
    %$kids = () if $kids;

    # Disconnect
    $self->{dbh}->disconnect unless $self->{dbh}->{Kids};

    # Delete parameters
    delete $self->{$_} foreach qw/dbh on_connect _connect_cb/;
  };

  # Return object
  $self;
};


# Initialize database
sub _init { 1 };


# Connect with database
sub _connect {
  my $self = shift;

  croak 'No database given' unless $self->{dsn};

  # DBI Connect
  my $dbh = DBI->connect(
    $self->{dsn},
    $self->{user} // undef,
    $self->_password,
    {
      PrintError => 0,
      RaiseError => 0,
      AutoCommit => 1,
      @_
    });

  # Unable to connect to database
  carp $DBI::errstr and return unless $dbh;

  # Store database handle
  $self->{dbh} = $dbh;

  # Save process id
  $self->{pid} = $$;

  # Save thread id
  $self->{tid} = threads->tid if $INC{'threads.pm'};

  # Emit all on_connect events
  foreach (values %{ $self->{on_connect} }) {
    $_->( $self, $dbh );
  };

  # Return handle
  $dbh;
};


# Password closure should prevent accidentally overt passwords
{
  # Password hash
  my %pwd;

  # Password method
  sub _password {
    my $id = shift->{_id};
    my $pwd_set = shift;

    my ($this) = caller(0);

    # Request only allowed in this namespace
    return if index(__PACKAGE__, $this) != 0;

    # Return password
    unless (defined $pwd_set) {
      return $pwd{$id};
    }

    # Delete password
    unless ($pwd_set) {
      delete $pwd{$id};
    }

    # Set password
    else {

      # Password can only be set on construction
      for ((caller(1))[3]) {
	m/::new$/o or return;
	index($_, __PACKAGE__) == 0 or return;
	!$pwd{$id} or return;
	$pwd{$id} = $pwd_set;
      };
    };
  };
};


# Get table name
sub _table_name {
  my $self = shift;

  # Table name
  my $table;
  unless (exists $self->{table}) {
    return shift(@{ $_[0] }) unless ref $_[0]->[0];
  }

  # Table object
  else {

    # Join table object not allowed
    return $self->{table} unless ref $self->{table};
  };

  return;
};


# Get table object
sub _table_obj {
  my $self = shift;

  my $tables;
  my ($fields, $pairs) = ([], []);

  # Not a table object
  unless (exists $self->{table}) {

    my $table = shift( @{ shift @_ } );

    # Table name as a string
    unless (ref $table) {
      $tables = [ $table ];
    }

    # Join tables
    else {
      return _join_tables( $table );
    };
  }

  # A table object
  else {

    # joined table
    if (ref $self->{table}) {
      return @{ $self->{table} };
    }

    # Table name
    else {
      $tables = [ $self->{table} ];
    };
  };

  return ($tables, $fields, $pairs);
};


# Join tables
sub _join_tables {
  my @join = @{ shift @_ };

  my (@tables, @fields, @pairs, $treatment);
  my %field_alias;
  my %marker;

  # Parse table array
  while (@join) {

    # Table name
    my $table = shift @join;

    # Check table name
    my $t_alias = $2 if $table =~ s/^([^:]+?):([^:]+?)$/$1 $2/o;

    # Push table
    push(@tables, $table);

    # Set prefix
    my $prefix = $t_alias ? $t_alias : $table;

    if (my $ref = ref $join[0]) {

      # Remember aliases
      my %alias;

      # Field array
      if ($ref eq 'ARRAY') {

	my $field_array = shift @join;

	my $f_prefix = '';

	# Has a hash next to it
	if (ref $join[0] && ref $join[0] eq 'HASH') {

	  # Set Prefix if given
	  # Todo: Is this documented?
	  if (exists $join[0]->{-prefix}) {
	    $f_prefix = delete $join[0]->{-prefix};
	    $f_prefix = _clean_alias($prefix) . '_' if $f_prefix eq '*';
	  };
	};

	# Reformat field values
	my $reformat = [
	  map {

	    # Is a reference
	    unless (ref $_) {

	      # Set alias semi explicitely
	      if (index($_, ':') == -1) {
		$_ .= ':~' . $f_prefix . _clean_alias($_);
	      };

	      # Field is not a function
	      if (index($_, '(') == -1) {
		$_ = "$prefix.$_" if index($_, '.') == -1;
	      }

	      # Field is a function
	      else {
		s/((?:\(|$FIELD_OP_REGEX)\s*)($KEY_REGEX_NOPREF)
                  (\s*(?:$FIELD_OP_REGEX|\)))/$1$prefix\.$2$3/ogx;
	      };

	    };

	    $_;
	  } @$field_array
	];

	# Automatically prepend table and, if not given, alias
	(my $fields, $treatment, my $alias) = _fields($t_alias, $reformat);

	# Set alias for markers
	# $alias{$_} = 1 foreach keys %$alias;
	while (my ($key, $val) = each %$alias) {
	  $field_alias{$key} = $alias{$key} = $val ;
	};

	# TODO: only use alias if necessary, as they can't be used in WHERE!

	push(@fields, $fields) if $fields;
      }

      # Add prepended *
      else {
	push(@fields, "$prefix.*");
      };

      # Marker hash reference
      if (ref $join[0] && ref $join[0] eq 'HASH') {
	my $hash = shift @join;

	# Add database fields to marker hash
	while (my ($key, $value) = each %$hash) {

	  # TODO: Does this work?
	  unless ($alias{$key}) {
	    $key = "$prefix.$key" if $key =~ $KEY_REGEX_NOPREF;
	  }
	  else {
	    $key = $alias{$key};
	  };

	  # Prefix, if not an explicite alias
	  foreach (ref $value ? @$value : $value) {

	    my $array = ($marker{$_} //= []);
	    push(@$array, $key);
	  };
	};
      };
    };
  };

  # Create condition pairs based on markers
  my ($ind, $fields);
  while (($ind, $fields) = each %marker) {
    my $field = shift(@$fields);
    foreach (@$fields) {
      push(
	@pairs,
	"$field " . ($ind < 0 ? '!' : '') . "= $_"
      );
    };
  };

  # Return join initialised values
  return (\@tables, \@fields, \@pairs, $treatment, \%field_alias);
};


# Get pairs and values
sub _get_pairs {
  my (@pairs, @values, %prep);

  # Get alias for fields
  my $alias = @_ == 2 ? pop @_ : {};

  while (my ($key, $value) = each %{ $_[0] }) {

    # Not a valid key
    unless ($key =~ m/^-?$KEY_REGEX$/o) {
      carp "$key is not a valid Oro key" and next;
    };

    if (substr($key, 0, 1) ne '-') {

      $key = exists $alias->{$key} ? $alias->{$key} : $key;

      # Equality
      unless (ref $value) {

	# NULL value
	unless (defined $value) {
	  push(@pairs, "$key IS NULL");
	}

	# Simple value
	else {

	  push(@pairs, "$key = ?"),
	    push(@values, $value);
	}
      }

      # Element of
      elsif (ref $value eq 'ARRAY') {
	# Undefined values in the array are not specified
	# as ' IN (NULL, ...)' does not work
	push (@pairs, "$key IN (" . _q($value) . ')' ),
	  push(@values, @$value);
      }

      # Operators
      elsif (ref $value eq 'HASH') {
	while (my ($op, $val) = each %$value) {
	  if ($op =~ $OP_REGEX) {
	    for ($op) {

	      # Uppercase
	      $_ = uc;

	      # Translate negation
	      s{^(?:NOT_|!(?=[MLGRB]))}{NOT };

	      # Translate literal compare operators
	      tr/GLENTQ/><=!/d if $_ =~ m/^(?:[GL][TE]|NE|EQ)$/o;
	      s/==/=/o;
	    };

	    # Array operators
	    if (ref $val && ref $val eq 'ARRAY') {

	      # Between operator
	      if (index($op, 'BETWEEN') >= 0) {
		push(@pairs, "$key $op ? AND ?"),
		  push(@values, @{$val}[0, 1]);
	      }

	      # Not element of
	      elsif ($op =~ /^NOT( IN)?$/) {
		# Undefined values in the array are not specified
		# as ' NOT IN (NULL, ...)' does not work

		push(@pairs, "$key NOT IN (" . _q($val) . ')' ),
		  push(@values, @$val);
	      };
	    }

	    # Simple operator
	    else {
	      my $p = "$key $op ";

	      # Value is an object
	      if (blessed $val) {
		$val = _stringify($val) or
		  carp "Unknown Oro value $key $op $val" and next;
	      };

	      # Defined value
	      if (defined $val) {
		$p .= '?';
		push(@values, $val);
	      }

	      # Null value
	      else {
		$p .= 'NULL';
	      };

	      push(@pairs, $p);
	    };

	  } else {
	    carp "Unknown Oro operator $key $op $val" and next;
	  }
	}
      }

      # Stringifiable object
      elsif ($value = _stringify($value)) {

	# Simple object
	push(@pairs, "$key = ?"),
	  push(@values, $value);
      }

      # Unknown pair
      else {
	carp "Unknown Oro pair $key, $value" and next;
      };
    }

    # Restriction of the result set
    else {
      $key = lc $key;

      # Limit and Offset restriction
      if ($key ~~ [qw/-limit -offset -distinct/]) {
	$prep{substr($key, 1)} = $value if $value =~ m/^\d+$/o;
      }

      # Order restriction
      elsif ($key =~ s/^-(order|group)(?:[-_]by)?$/$1/) {

	# Already array and group
	if ($key eq 'group' && ref $value) {
	  if (ref $value->[-1] && ref $value->[-1] eq 'HASH') {
	    $prep{having} = pop @$value;

	    unless (@$value) {
	      carp '"Having" without "Group" is not allowed' and next;
	    };
	  };
	};

	my @field_array;

	# Check group values
	foreach (ref $value ? @$value : $value) {

	  # Valid order/group_by value
	  if ($_ =~ $VALID_GROUPORDER_REGEX) {
	    s/^([\-\+])//o;
	    push(@field_array, $1 && $1 eq '-' ? "$_ DESC" : $_ );
	  }

	  # Invalid order/group_by value
	  else {
	    carp "$_ is not a valid Oro $key restriction";
	  };
	};

	$prep{$key} = join(', ', @field_array) if scalar @field_array;
      }

      # Cache
      elsif ($key eq '-cache') {
	my $chi = delete $value->{chi};

	# Check chi existence
	if ($chi) {
	  $prep{cache} = [ $chi, delete $value->{key} // '', $value ];
	}

	# No chi given
	else {
	  carp 'No CHI driver given for cache';
	};
      };
    };
  };

  return (\@pairs, \@values, (keys %prep ? \%prep : undef));
};


# Get fields
sub _fields {
  my $table = shift;

  my (%treatment, %alias, @fields);

  foreach ( @{$_[0]} ) {

    # Ordinary String
    unless (ref $_) {

      # Valid field
      if ($_ =~ $VALID_FIELD_REGEX) {
	push(@fields, $_);
      }

      # Invalid field
      else {
	carp "$_ is not a valid Oro field value"
      };
    }

    # Treatment
    elsif (ref $_ eq 'ARRAY') {
      my ($sub, $alias) = @$_;
      my ($sql, $inner_sub) = $sub->($table);
      ($sql, $inner_sub, my @param) = $sql->($table) if ref $sql;

      $treatment{ $alias } = [$inner_sub, @param ] if $inner_sub;
      push(@fields, "$sql:$alias");
    };
  };

  my $fields = join(', ', @fields);

  # Return if no alias fields exist
  return $fields unless $fields =~ m/[\.:=]/o;

  # Join with alias fields
  return (
    join(
      ', ',
      map {
	# Explicite field alias
	if ($_ =~ $FIELD_REST_RE) {

	  # ~ indicates rather not explicite alias
	  # Will only be set in case of agregate functions
	  # TODO: if ($2 eq ':' && index($1,'(') >= 0);
	  $alias{$3} = $1;
	  qq{$1 AS `$3`};
	}

	# Implicite field alias
	elsif (m/^(?:.+?)\.(?:[^\.]+?)$/) {
	  my $cl = _clean_alias $_;
	  $alias{$cl} = qq{$_ AS `$cl`};
	}

	# Field value
	else {
	  $_
	};
      } @fields
    ),
    (%treatment ? \%treatment : undef),
    \%alias
  );
};


# Restrictions
sub _restrictions {
  my ($prep, $values) = @_;
  my $sql = '';

  # Group restriction
  if ($prep->{group}) {
    $sql .= ' GROUP BY ' . delete $prep->{group};

    # Having restriction
    if ($prep->{having}) {

      # Get conditions
      my ($cond_pairs, $cond_values) = _get_pairs(
	delete $prep->{having}
      );

      # Conditions given
      if (@$cond_pairs) {

	# Append having condition
	$sql .= ' HAVING ' . join(' AND ', @$cond_pairs);

	# Append values
	push(@$values, @$cond_values);
      };
    };
  };

  # Order restriction
  if (exists $prep->{order}) {
    $sql .= ' ORDER BY ' . delete $prep->{order};
  };

  # Limit restriction
  if ($prep->{limit}) {
    $sql .= ' LIMIT ?';
    push(@$values, delete $prep->{limit});

    # Offset restriction
    if (defined $prep->{offset}) {
      $sql .= ' OFFSET ?';
      push(@$values, delete $prep->{offset});
    };
  };

  $sql;
};


# Check for stringification of blessed values
sub _stringify {
  my $ref = blessed $_[0];
  if (index(($_ = "$_[0]"), $ref) != 0) {
    return $_;
  };
  undef;
}

# Clean alias string
sub _clean_alias {
  for (my $x = shift) {
    tr/ ()[]"$@#./_/s;
    s/[_\s]+$//;
    return lc $x;
  };
};


# Questionmark string
sub _q {
  join(', ', ('?') x scalar( @{ $_[0] } ));
};


1;


__END__


=pod

=head1 NAME

DBIx::Oro - Simple Relational Database Accessor


=head1 SYNOPSIS

  use DBIx::Oro;

  # Create new object
  my $oro = DBIx::Oro->new(

    # Create an SQLite in-memory DB and initialize
    ':memory:' => sub {

      # Initialize tables with direct SQL
      $_->do(
        'CREATE TABLE User (
           id    INTEGER PRIMARY KEY,
           name  TEXT,
           age   TEXT
        )'
      ) or return -1;
    }
  );

  # Execute SQL directly
  $oro->do(
    'CREATE TABLE Post (
       time     INTEGER,
       msg      TEXT,
       user_id  INTEGER
    )'
  );

  # Wrap multiple actions in transactions
  $oro->txn(
    sub {

      # Insert simple data
      my $rv = $_->insert(User => {
        name => 'Akron',
        age  => '20'
      });

      # Easily rollback transaction
      return -1 unless $rv;

      # Get latest inserted id
      my $user_id = $_->last_insert_id;

      # Bulk insert data with default values
      $_->insert(Post => [
        [ time => time ],
        [ user_id => $user_id ],
        'msg'] => (
          ['Hello World!'],
	  ['Seems to work!'],
	  ['I can insert bulk messages ...'],
	  ['And I can stop.']
        )
      ) or return -1;
  });

  # Load a dataset based on a unique condition
  my $user = $oro->load(User => { name => 'Akron' });

  print $user->{age}; # '20'

  # Count the number of entries on a table
  print $oro->count('Post'); # '4'

  # Select multiple datasets based on conditions
  my $msgs = $oro->select(Post => ['msg'] => {
    msg => { like => '%wo%' }
  });

  # Results are simple datastructures
  print $_->{msg} . "\n" foreach @$msgs;
  # 'Hello World!'
  # 'Seems to work!'

  # Create joined tables
  my $join = $oro2->table([
    User => ['name'] => { id => 1 },
    Post => ['msg']  => { user_id => 1 }
  ]);

  # Select on joined tables and send data to a callback
  $join->select({
      name   => 'Akron',
      msg    => { not_glob => 'And*' },
      -limit => 2
    } => sub {
      print $_->{name}, ': ', $_->{msg}, "\n";
    });
  # Akron: Hello World!
  # Akron: I can insert bulk messages ...

  # Investigate generated SQL data for debugging
  print $join->last_sql;

  # 'SELECT User.name AS `name`, Post.msg AS `msg`
  # FROM User, Post WHERE User.id = Post.user_id
  # AND Post.msg NOT GLOB ? AND User.name = ?
  # LIMIT ?'


=head1 DESCRIPTION

L<DBIx::Oro> is a database accessor that provides
basic functionalities to work with simple relational databases,
especially in a web environment.

Its aim is not to be a complete abstract replacement
for SQL communication with DBI, but to make common tasks easier.
For now it's focused on SQLite - but first steps to make it less
dependent on SQLite are done. It should be fork- and thread-safe.

See L<Driver::SQLite|DBIx::Oro::Driver::SQLite>
and L<Driver::MySQL|DBIx::Oro::Driver::MySQL>
for database specific drivers.

B<DBIx::Oro is a development release!
Do not rely on any API methods, especially
on those marked as experimental.>


=head1 ATTRIBUTES

=head2 dbh

  my $dbh = $oro->dbh;
  $oro->dbh(DBI->connect('...'));

The DBI database handle.


=head2 driver

  print $oro->driver;

The driver (e.g., C<SQLite> or C<MySQL>) of the Oro instance.


=head2 last_insert_id

  my $id = $oro->last_insert_id;

The globally last inserted id regarding the database connection.


=head2 last_sql

  print $oro->last_sql;
  my ($sql, $from_cache) = $oro->last_sql;

The last executed SQL command.

In array context this will also return a value indicating
if the request was a real database request.
If the last result was returned by a cache, the value is true, otherwise false.

B<Note> This is for debugging purposes only - the returned SQL may not be
valid due to reformatting.

B<The array return is EXPERIMENTAL and may change without warnings.>


=head1 METHODS

=head2 new

  my $oro = DBIx::Oro->new('test.sqlite');
  $oro = DBIx::Oro->new('test.sqlite' => sub {
    shift->do(
      'CREATE TABLE Person (
          id    INTEGER PRIMARY KEY,
          name  TEXT NOT NULL,
          age   INTEGER
      )');
  });
  $oro = DBIx::Oro->new(
    driver   => 'MySQL',
    database => 'TestDB',
    user     => 'root',
    password => ''
  );

Creates a new Oro database handle.

Accepts a C<driver> attribute (supported are currently
C<SQLite> and C<MySQL>) all attributes
accepted by this specific driver.

If only a string value is given, this will be treated as
a filename of a L<DBIx::Oro::Driver::SQLite> object.
If the filename is C<:memory:>, this will be an in-memory SQLite database.
If the database file does not already exist, it is created.
An additional callback function may be passed, that serves
as the C<init> attribute of the SQLite
Driver's L<new|DBIx::Oro::Driver::SQLite/new>.

B<The class name of the return object may change without warnings!>


=head2 insert

  $oro->insert(Person => {
    id   => 4,
    name => 'Peter',
    age  => 24
  });
  $oro->insert(Person =>
    ['id', 'name'] => [4, 'Peter'], [5, 'Sabine']
  );

Inserts a new row to a given table for single insertions.

Expects the table name and a hash reference of values to insert.
For multiple insertions, it expects the table name
to insert, an array reference of the column names and an arbitrary
long array of array references of values to insert.

  $oro->insert(Person =>
    ['prename', [ surname => 'Meier' ]] =>
      map { [$_] } qw/Peter Sabine Frank/
  );

For multiple insertions with defaults, the array reference for column
names can contain array references itself with a column name followed by
the default value. This value is inserted for each inserted entry
and is especially useful for C<n:m> relation tables.


=head2 update

  my $rows = $oro->update(Person => { name => 'Daniel' }, { id => 4 });

Updates values of an existing row of a given table.

Expects the table name to update, a hash reference of values to update,
and optionally a hash reference with conditions, the rows have to fulfill.
In case of scalar values, identity is tested. In case of array references,
it is tested, if the field value is an element of the set.

Returns the number of rows affected.


=head2 merge

  $oro->merge(Person => { age => 29 }, { name => 'Daniel' });

Updates values of an existing row of a given table,
otherwise inserts them (so called I<upsert>).

Expects the table name to update or insert, a hash reference of
values to update or insert, and optionally a hash reference with conditions,
the rows have to fulfill.
In case of scalar values, identity is tested. In case of array references,
it is tested, if the field value is an element of the set.

Scalar condition values will be inserted, if the fields do not exist.


=head2 select

  my $users = $oro->select('Person');
  $users = $oro->select(Person => ['id', 'name']);
  $users = $oro->select(Person =>
    ['id'] => {
      age  => 24,
      name => ['Daniel', 'Sabine']
    });
  $users = $oro->select(Person => ['name:displayName']);

  $oro->select(
    Person => sub {
      print $_->{id}, "\n";
      return -1 if $_->{name} eq 'Peter';
    });

  my $age = 0;
  $oro->select(
    Person => ['id', 'age'] => {
      name => { like => 'Dani%' }} =>
        sub {
          print $_->{id}, "\n";
          $age += $_->{age};
          return -1 if $age >= 100;
    });


Returns an array reference of rows as hash references of a given table,
that meet a given condition.

Expects the table name of the selection and optionally an array reference
of fields, optionally a hash reference with conditions and restrictions
all rows have to fulfill, and optionally a callback,
which is released after each row, passing the row as a hash reference.

If a callback is given, the method has no return value.
If the callback returns -1, the data fetching is aborted.

In case of scalar values, identity is tested for the condition.
In case of array references, it is tested, if the field value is an element of the set.
In case of hash references, the keys of the hash represent operators to
test with (see L<below|/Operators>).

Fields can be column names or SQL functions.
With a colon you can define aliases of field names,
like with C<count(field):field_count>.

B<The callback is EXPERIMENTAL and may change without warnings.>


=head3 Operators

When checking with hash references, several operators are supported.

  my $users = $oro->select(
    Person => {
      name => {
        like     => '%e%',
        not_glob => 'M*'
      },
      age => {
        between => [18, 48],
        ne      => 30,
        not     => [45,46]
      }
    }
  );

Supported operators are C<E<lt> (lt)>, C<E<gt> (gt)>, C<= (eq)>,
C<E<lt>= (le)>, C<E<gt>= (ge)>, C<!= (ne)>.
String comparison operators like C<like> and similar are supported.
To negate the latter operators you can prepend C<not_>.
The C<between> and C<not_between> operators are special as they expect
a two value array reference as their operand. The single C<not> operator
accepts an array reference as a set and is true, if the value is not
element of the set.
To test for existence, use C<value =E<gt> { not =E<gt> undef }>.

Multiple operators for checking with the same column are supported.

B<Operators are EXPERIMENTAL and may change without warnings.>


=head3 Restrictions

In addition to conditions, the selection can be restricted by using
special restriction parameters, all prepended by a C<-> symbol:

  my $users = $oro->select(
    Person => {
      -order    => ['-age','name'],
      -group    => [ age => { age => { gt => 42 } } ]
      -offset   => 1,
      -limit    => 5,
      -distinct => 1
    }
  );

=over 2

=item

C<-order>

Sorts the result set by field names.
Field names can be scalars or array references of field names ordered
by priority.
A leading minus of the field name will use descending,
otherwise ascending order.

=item

C<-group>

Groups the result set by field names.
Especially useful with aggregation operators like C<count()>.
Field names can be scalars or array references of field names ordered
by priority.
In case of an array reference, the final element can be a hash
reference, giving a C<having> condition.

=item

C<-limit>

Limits the number of rows in the result set.

=item

C<-offset>

Sets the offset of the result set.

=item

C<-distinct>

Boolean value. If set to a true value, only distinct rows are returned.

=back


=head3 Joined Tables

Instead of preparing a select on only one table, it's possible to
use any number of tables and perform a simple equi-join:

  $oro->select(
    [
      Person =>    ['name:author', 'age'] => { id => 1 },
      Book =>      ['title'] => { author_id => 1, publisher_id => 2 },
      Publisher => ['name:publisher', 'id:pub_id'] => { id => 2 }
    ] => {
      author => 'Akron'
    }
  );

Join-Selects accept an array reference with a sequence of
table names, optional field array references and optional hash references
containing numerical markers for the join.
If the field array reference is not given, all columns of the
table are selected. If the array reference is empty, no columns of the
table are selected.

With a colon you can define aliases for the field names.

The join marker hash reference has field names as keys
and numerical markers or array references including numerical markers as values.
Fields with identical markers greater or equal than C<0> will have
identical content, fields with identical markers littler than C<0>
will have different content.

After the join table array reference, the optional hash
reference with conditions and restrictions and an optional
callback may follow.

B<Joins are EXPERIMENTAL and may change without warnings.>


=head3 Treatments

Sometimes field functions and returned values shall be treated
in a special way.
By handing over subroutines, L<select|/select> as well as L<load|/load> allow
for these treatments.


  my $name = sub {
    return ('name', sub { uc $_[0] });
  };
  $oro->select(Person => ['age', [ $name => 'name'] ]);


This example returns all values in the C<name> column in uppercase.
Treatments are array references in the field array, with the first
element being a treatment subroutine reference and the second element
being the alias of the column.

The treatment subroutine returns a field value (an SQL string),
optionally an anonymous subroutine that is executed after each
returned value, and optionally an array of values to pass to the inner
subroutine.
The first parameter the inner subroutine has to handle
is the value to treat, following the optional treatment parameters.
The treatment returns the treated value (that does not have to be a string).

Outer subroutines are executed as long as the first value is not a string
value. The only parameter passed to the outer subroutine is the
current table name.

See the L<SQLite Driver|DBIx::Oro::Driver::SQLite> for examples of treatments.

B<Treatments are HEAVILY EXPERIMENTAL and may change without warnings.>


=head3 Caching

  use CHI;
  my $hash = {};
  my $cache = CHI->new(
    driver => 'Memory',
    datastore => $hash
  );

  my $users = $oro->select(
    Person => {
      -cache => {
        chi        => $cache,
        key        => 'all_persons',
        expires_in => '10 min'
      }
    }
  );

Selected results can be directly cached by using the C<-cache>
keyword. It accepts a hash reference with the parameter C<chi>
containing the cache object and C<key> containing the key
for caching. If no key is given, the SQL statement is used
as the key. All other parameters are transferred to the C<set>
method of the cache.

B<Note:> Although the parameter is called C<chi>, all caching
objects granting the limited functionalities of C<set> and C<get>
methods are valid (e.g., L<Cache::Cache>, L<Mojo::Cache>).

B<Caching is EXPERIMENTAL and may change without warnings.>


=head2 load

  my $user  = $oro->load(Person, { id => 4 });
  my $user  = $oro->load(Person, ['name'], { id => 4 });
  my $count = $oro->load(Person, ['count(*):persons']);

Returns a single hash reference of a given table,
that meets a given condition.

Expects the table name of selection, an optional array reference of fields
to return and a hash reference with conditions, the rows have to fulfill.
Normally this will include the primary key.
Restrictions as well as the caching system can be applied as with
L<select|/select>.
In case of scalar values, identity is tested.
In case of array references, it is tested, if the field value is an
element of the set.
Fields can be column names or functions. With a colon you can define
aliases for the field names.


=head2 count

  my $persons = $oro->count('Person');
  my $pauls   = $oro->count('Person' => { name => 'Paul' });

Returns the number of rows of a table.

Expects the table name and a hash reference with conditions,
the rows have to fulfill.
Caching can be applied as with L<select|/select>.


=head2 delete

  my $rows = $oro->delete(Person => { id => 4 });

Deletes rows of a given table, that meet a given condition.

Expects the table name of selection and optionally a hash reference
with conditions and restrictions, the rows have to fulfill.
In case of scalar values, identity is tested for the condition.
In case of array references, it is tested, if the field value is an
element of the set.
Restrictions can be applied as with L<select|/select>.

Returns the number of rows that were deleted.


=head2 table

  # Table names
  my $person = $oro->table('Person');
  print $person->count;
  my $person = $person->load({ id => 2 });
  my $persons = $person->select({ name => 'Paul' });
  $person->insert({ name => 'Ringo' });
  $person->delete;

  # Joined tables
  my $books = $oro->table(
    [
      Person =>    ['name:author', 'age:age'] => { id => 1 },
      Book =>      ['title'] => { author_id => 1, publisher_id => 2 },
      Publisher => ['name:publisher', 'id:pub_id'] => { id => 2 }
    ]
  );
  $books->select({ author => 'Akron' });
  print $books->count;

Returns a new Oro object with a predefined table or joined tables.

Allows to omit the first table argument for the methods
L<select|/select>, L<load|/load>, L<count|/count> and - in case of non-joined-tables -
for L<insert|/insert>, L<update|/update>, L<merge|/merge>, and L<delete|/delete>.

In conjunction with a joined table this can be seen as an I<ad hoc view>.

B<This method is EXPERIMENTAL and may change without warnings.>


=head2 txn

  $oro->txn(
    sub {
      foreach (1..100) {
        $oro->insert(Person => { name => 'Peter'.$_ }) or return -1;
      };
      $oro->delete(Person => { id => 400 });

      $oro->txn(
        sub {
          $_->insert('Person' => { name => 'Fry' }) or return -1;
        }) or return -1;
    });

Wrap transactions.

Expects an anonymous subroutine containing all actions.
If the subroutine returns -1, the transactional data will be omitted.
Otherwise the actions will be released.
Transactions established with this method can be securely nested
(although inner transactions may not be true transactions depending
on the driver).


=head2 do

  $oro->do(
    'CREATE TABLE Person (
        id   INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
     )');

Executes direct SQL code.

This is a wrapper for the L<do|DBI/do> method of DBI (but fork- and thread-safe).


=head2 explain

  print $oro->explain(
    'SELECT ? FROM Person', ['name']
  );

Returns the query plan for a given query as a line-breaked string.

B<This method is EXPERIMENTAL and may change without warnings.>


=head2 prep_and_exec

  my ($rv, $sth) = $oro->prep_and_exec(
    'SELECT ? FROM Person', ['name'], 'cached'
  );

  if ($rv) {
    my $row;
    while ($row = $sth->fetchrow_hashref) {
      print $row->{name};
      if ($name eq 'Fry') {
        $sth->finish;
        last;
      };
    };
  };

Prepare and execute an SQL statement with all checkings.
Returns the return value (on error C<false>, otherwise C<true>,
e.g. the number of modified rows) and - in an array context -
the statement handle.

Accepts the SQL statement, parameters for binding in an array
reference and optionally a boolean value, if the prepared
statement should be cached by L<DBI>.


=head1 EVENTS

=head2 on_connect

  $oro->on_connect(
    sub { $log->debug('New connection established') }
  );

  if ($oro->on_connect(
    my_event => sub {
      shift->insert(Log => { msg => 'reconnect' } )
    })) {
    print 'Event newly established!';
  };

Attaches a callback for execution in case of newly established
database connections.

The first argument passed to the anonymous subroutine is the Oro object,
the second one is the newly established database connection.
Prepending a string with a name will prevent from adding an
event multiple times - adding the event again will be ignored.

Returns a true value in case the event is newly established,
otherwise false.

Events will be emitted in an unparticular order.

B<This event is EXPERIMENTAL and may change without warnings.>


=head1 DEPENDENCIES

L<DBI>,
L<DBD::SQLite>.


=head1 INSTALL

When not installing via a package manager, CPAN or cpanm,
you can install Oro manually, using

  $ perl Makefile.PL
  $ make
  $ make test
  $ sudo make install

By default, C<make test> will test all common and driver specific
tests for the SQLite driver.
By using C<make test TEST_DB={Driver}> all common and driver specific
tests for the given driver are run, e.g. C<make test TEST_DB=MySQL>.
The constructor information can be written as a perl data structure
in C<t/test_db.pl>, for example:

  {
    MySQL => {
      database => 'test',
      host     => 'localhost',
      username => 'MyTestUser',
      password => 'h3z6z8vvfju'
    }
  }


=head1 ACKNOWLEDGEMENT

Partly inspired by L<ORLite>, written by Adam Kennedy.
Some code is based on L<DBIx::Connector>, written by David E. Wheeler.
Without me knowing (it's a shame!), some of the concepts are quite similar
to L<SQL::Abstract>, written by Nathan Wiger et al.


=head1 AVAILABILITY

  https://github.com/Akron/DBIx-Oro


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2013, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut

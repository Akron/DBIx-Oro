package DBIx::Oro;
use strict;
use warnings;

our $VERSION = '0.22';

use v5.10.1;

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
  $param{created} //= 0;

  # Get callback
  my $cb = delete $param{init} if $param{init} &&
    (ref $param{init} || '') eq 'CODE';

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

  # Import SQL file
  my $import    = delete $param{import};
  my $import_cb = delete $param{import_cb};

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
	  $cb->($self) if $cb;

	  return 1;
	})
    ) {

      # SQLite database
      if ($self->driver eq 'SQLite' &&
	    $self->file &&
	      index($self->file, ':') != 0) {
	unlink $self->file;
      };

      # Not successful
      $self = undef;
      return;
    };
  };


  # Return Oro instance
  $self;
};


# New table object
sub table {
  my $self = shift;

  my %param;
  # Joined table
  $param{table} = do {
    if (ref($_[0])) {
      [ _join_tables( shift(@_) ) ];
    }

    # Table name
    else {
      shift;
    };
  };

  # Clone parameters
  foreach (qw/dbh created in_txn
              savepoint pid tid
	      dsn _connect_cb
	      on_connect/) {
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
  if ($last_sql =~ m/(?:UNION|\?(?:, \?){3,})/) {

    our $c;

    # Count Union selects
    state $UNION_RE =
      qr/(?{$c=1})(SELECT \?(?:, \?)*)(?: UNION \1(?{$c++})){3,}/;

    # Count recurring placeholders
    state $PLACEHOLDER_RE =
      qr/(?{$c=1})\?(?:, \?(?{$c++})){3,}/;

    # Rewrite placeholders with count
    for ($last_sql) {
      s/$UNION_RE/WITH $c x UNION $1/og;
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


# Database was just created
sub created {
  $_[0]->{created};
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

  # Create insert string
  my $sql = 'INSERT ';

  if ($prop) {
    given ($prop->{-on_conflict}) {
      when ('replace') { $sql = 'REPLACE '};
      when ('ignore')  { $sql .= 'IGNORE '};
    };
  };

  # Single insert
  if (ref $_[0] eq 'HASH') {

    # Param
    my %param = %{ shift(@_) };

    # Create insert arrays
    my (@keys, @values);

    while (my ($key, $value) = each %param) {
      next unless $key =~ $KEY_REGEX;
      push(@keys, $key), push(@values, $value);
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
      push(@default_keys, $key), push(@default, $value);
    };

    # Unshift default keys to front
    unshift(@keys, @default_keys);

    $sql .= 'INTO ' . $table . ' (' . join(', ', @keys) . ') ';

    # Add data in brackets
    $sql .= _q(\@keys) x ( scalar(@_) - 1 );

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
  return unless $pairs ~~ /^$KEY_REGEX\s+(?:=|IS)/o;

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
      $join_pairs, $treatment) = _table_obj($self, \@_);

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
      ($pairs, $values, $prep) = _get_pairs( shift(@_) );

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

    # Add limitation t the condition
    if (ref($param[-1]) eq 'HASH') {
      $param[-1]->{-limit} = 1;
    }

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
  my ($tables, $fields, $join_pairs, $treatment) =
    _table_obj($self, \@_);
  my @pairs = @$join_pairs;

  # Build sql
  my $sql = 'SELECT ' . join(', ', 'count(1)', @$fields) .
            ' FROM '  . join(', ', @$tables);

  # Ignore fields
  shift if $_[0] && ref $_[0] eq 'ARRAY';

  # Get conditions
  my ($pairs, $values, $prep);
  if ($_[0] && ref $_[0] eq 'HASH') {
    ($pairs, $values, $prep) = _get_pairs( shift(@_) );
    push(@pairs, @$pairs) if $pairs->[0];
  };

  # Add where clause
  $sql .= ' WHERE ' . join(' AND ', @pairs) if @pairs;
  $sql .= ' LIMIT 1';

  my $result;

  # Check cache
  my ($chi, $key, $chi_param);
  if ($prep && $prep->{cache}) {
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
  return 0 if !$rv || $rv ne '0E0';

  # Return count
  $result = $sth->fetchrow_arrayref->[0];
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
  my $dbh = shift->dbh;
  my (@rv) = $dbh->do( @_ );

  # Error
  carp $dbh->errstr . ' in "' . $_[0] . '"' if $dbh->err;
  return @rv;
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
    my $rv = $_[0]->($self);
    if (!$rv || $rv != -1) {
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
    my $sp = 'orosp_' . $$ . '_';

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
    if (!$rv || $rv != -1) {
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
  my $cb = pop;

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
  $_[0]->dbh->last_insert_id;
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
# Todo: Does this work with multiple Objects?
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


# Import files
sub import_sql {
  my $self = shift;

  # Get callback
  my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

  my $files = @_ > 1 ? \@_ : shift;

  # Import subroutine
  my $import = sub {
    my $file = shift;

    # No file given
    return unless $file;

    if (open(SQL, '<:utf8', $file )) {
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
  }

  # Single file import
  else {
    return $import->($files);
  };

  return;
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

	if (ref $join[0] && ref $join[0] eq 'HASH') {

	  # Set Prefix if given.
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
		$_ = "$prefix.$_";
	      }

	      # Field is a function
	      else {
		s/((?:\(|$FIELD_OP_REGEX)\s*)($KEY_REGEX)
                  (\s*(?:$FIELD_OP_REGEX|\)))/$1$prefix\.$2$3/ogx;
	      };
	    };

	    $_;
	  } @$field_array
	];

	# Automatically prepend table and, if not given, alias
	(my $fields, $treatment, my $alias) = _fields($t_alias, $reformat);

	# Set alias for markers
	$alias{$_} = 1 foreach keys %$alias;

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

	  $key = "$prefix.$key" unless $alias{$key};

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
  return (\@tables, \@fields, \@pairs, $treatment);
};


# Get pairs and values
sub _get_pairs {
  my (@pairs, @values, %prep);

  while (my ($key, $value) = each %{ $_[0] }) {

    # Not a valid key
    unless ($key =~ m/^-?$KEY_REGEX$/o) {
      carp "$key is not a valid Oro key" and next;
    };

    if (substr($key, 0, 1) ne '-') {

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
	# as ' IN (NULL, ...) does not work
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
	    };

	    # Simple operator
	    if (index($op, 'BETWEEN') == -1) {
	      my $p = "$key $op ";

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
	    }

	    # Between operator
	    elsif (ref $val && ref $val eq 'ARRAY') {
	      push(@pairs, "$key $op ? AND ?"),
		push(@values, @{$val}[0, 1]);
	    };
	  }
	}
      }

      else {
	carp "Unknown operator $key" and next;
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
	  $prep{cache} = [$chi, delete $value->{key} // '', $value];
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

	  # ~ indicates rather not explicite
	  $alias{$3} = 1 if $2 eq ':';
	  qq{$1 AS "$3"};
	}

	# Implicite field alias
	elsif (m/^(?:.+?)\.(?:[^\.]+?)$/) {
	  $_ . ' AS "' . _clean_alias $_ . '"';
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
  };

  # Offset restriction
  if (defined $prep->{offset}) {
    $sql .= ' OFFSET ?';
    push(@$values, delete $prep->{offset});
  };

  $sql;
};


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

DBIx::Oro - Simple Database Accessor


=head1 SYNOPSIS

  use DBIx::Oro;

  my $oro = DBIx::Oro->new('file.sqlite');
  if ($oro->created) {
    $oro->do(
    'CREATE TABLE Person (
        id    INTEGER PRIMARY KEY,
        name  TEXT NOT NULL,
        age   INTEGER
     )'
    );
  };
  $oro->insert(Person => { name => 'Peter'});
  my $john = $oro->load(Person => { id => 4 });

  my $person = $oro->table('Person');
  my $peters = $person->select({ name => 'Peter' });


=head1 DESCRIPTION

L<DBIx::Oro> is a simple database accessor that provides
basic functionalities to work with simple databases, especially
in a web environment.

Its aim is not to be a complete abstract replacement
for SQL communication with DBI, but to make common tasks easier.
For now it is limited to SQLite. It should be fork- and thread-safe.

B<DBIx::Oro is in beta status. Do not rely on methods, especially
on these marked as experimental.>


=head1 ATTRIBUTES

=head2 C<created>

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

B<This attribute is EXPERIMENTAL and may change without warnings.>

=head2 C<dbh>

  my $dbh = $oro->dbh;
  $oro->dbh(DBI->connect('...'));

The DBI database handle.


=head2 C<driver>

  print $oro->driver;

The driver (e.g., 'SQLite') of the Oro instance.


=head2 C<last_insert_id>

  my $id = $oro->last_insert_id;

Returns the globally last inserted id regarding to the database connection.


=head2 C<last_sql>

  print $oro->last_sql;
  my ($sql, $from_cache) = $oro->last_sql;

The last executed SQL command.
In array context it returns the last executed SQL command
of the handle and a false value in case of a real database request.
If the last result was returned by a cache, the value is true.

This is for debugging purposes only - the returned SQL may not be
valid due to reformating.

B<The array return is EXPERIMENTAL and may change without warnings.>


=head1 METHODS


=head2 C<new>

  $oro = DBIx::Oro->new('test.sqlite');
  $oro = DBIx::Oro->new('test.sqlite' => sub {
    shift->do(
      'CREATE TABLE Person (
          id    INTEGER PRIMARY KEY,
          name  TEXT NOT NULL,
          age   INTEGER
      )');
  });

Creates a new Oro database handle.
If only a string value is given, this will default to
a L<DBIx::Oro::Driver::SQLite> object. The database will
be connected based on the given filename or in memory,
if the filename is ':memory:'.
If the database file does not already exist, it is created.
Accepts an optional callback that is only released, if
the database is newly created. The first parameter of
the callback function is the Oro-object.


=head2 C<insert>

  $oro->insert(Person => {
    id => 4,
    name => 'Peter',
    age => 24
  });
  $oro->insert(Person =>
    ['id', 'name'] => [4, 'Peter'], [5, 'Sabine']
  );

Inserts a new row to a given table for single insertions.
Expects the table name and a hash ref of values to insert.

For multiple insertions, it expects the table name
to insert, an arrayref of the column names and an arbitrary
long array of array references of values to insert.

  $oro->insert(Person =>
    ['prename', [ surname => 'Meier' ]] =>
      map { [$_] } qw/Peter Sabine Frank/
  );

For multiple insertions with defaults, the arrayref for column
names can contain array references with a column name and the
default value. This value is inserted for each inserted entry
and especially useful for n:m relation tables.


=head2 C<update>

  my $rows = $oro->update(Person => { name => 'Daniel' }, { id => 4 });

Updates values of an existing row of a given table.
Expects the table name to update, a hash ref of values to update,
and optionally a hash ref with conditions, the rows have to fulfill.
In case of scalar values, identity is tested. In case of array refs,
it is tested, if the field is an element of the set.
Returns the number of rows affected.


=head2 C<merge>

  $oro->merge(Person => { age => 29 }, { name => 'Daniel' });

Updates values of an existing row of a given table,
otherways inserts them (so called I<upsert>).
Expects the table name to update or insert, a hash ref of
values to update or insert, and optionally a hash ref with conditions,
the rows have to fulfill.
In case of scalar values, identity is tested. In case of array refs,
it is tested, if the field is an element of the set.
Scalar condition values will be inserted, if the fields do not exist.


=head2 C<select>

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
      say $_[0]->{id};
      return -1 if $_[0]->{name} eq 'Peter';
    });

  my $age = 0;
  $oro->select(
    Person => ['id', 'age'] => {
      name => { like => 'Dani%' }} =>
        sub {
          my $user = shift;
          say $user->{id};
          $age += $user->{age};
          return -1 if $age >= 100;
    });


Returns an array ref of hash refs of a given table,
that meets a given condition or releases a callback in this case.
Expects the table name of selection and optionally an array ref
of fields, optionally a hash ref with conditions and restrictions,
the rows have to fulfill, and optionally a callback,
which is released after each row.
If the callback returns -1, the data fetching is aborted.
In case of scalar values, identity is tested for the condition.
In case of array refs, it is tested, if the field is an element of the set.
In case of hash refs, the keys of the hash represent operators to
test with (see below).
Fields can be column names or functions.
With a colon you can define aliases for the field names.

=head3 Operators

When checking with hash refs, several operators are supported.

  my $users = $oro->select(
    Person => {
      name => {
        like     => '%e%',
        not_glob => 'M*'
      },
      age => {
        between => [18, 48],
        ne      => 30
      }
    }
  );

Supported operators are '<' ('lt'), '>' ('gt'), '=' ('eq'),
'<=' ('le'), '>=' ('ge'), '!=' ('ne').
String comparison operators like C<like> and similar are supported.
To negate the latter operators you can prepend 'not_'.
The 'between' and 'not_between' operators are special as they expect
a two value array as their operand.
To test for existence, use C<value =E<gt> { not =E<gt> undef }>.
Multiple operators for checking with the same column are supported.

B<Operators are EXPERIMENTAL and may change without warnings.>

=head3 Restrictions

In addition to conditions, the selection can be restricted by using
special restriction parameters:

  my $users = $oro->select(
    Person => {
      -order    => ['-age','name'],
      -group    => [age => { age => { gt => 42 } }]
      -offset   => 1,
      -limit    => 5,
      -distinct => 1
    }
  );

=over 2

=item C<-order>

Sorts the result set by field names.
Field names can be scalars or array references of field names ordered
by priority.
A leading minus of the field name will use descending order,
otherwise ascending order.

=item C<-group>

Groups the result set by field names.
Especially useful with aggregation operators like C<count()>.
Field names can be scalars or array references of field names ordered
by priority.
In case of an array reference, the final element can be a hash
reference for a C<having> condition.

=item C<-limit>

Limits the number of rows in the result set.

=item C<-offset>

Sets the offset of the result set.

=item C<-distinct>

Boolean value. If set to a true value, only distinct rows are returned.

=back

=head3 Joined Tables

Instead of preparing a select on only one table, it's possible to
use any number of tables and perform a simple join:

  $oro->select(
    [
      Person =>    ['name:author', 'age'] => { id => 1 },
      Book =>      ['title'] => { author_id => 1, publisher_id => 2 },
      Publisher => ['name:publisher', 'id:pub_id'] => { id => 2 }
    ] => {
      author => 'Akron'
    }
  );

Join-Selects accept an array reference with a sequences of
table names, optional field array refs and optional hash refs
containing numerical markers for the join.
If the field array ref does not exists, all columns of the
table are selected. If the array ref is empty, no columns of the
table are selected.
With a colon you can define aliases for the field names.
The join marker hash ref has field names as keys
and numerical markers or array refs of numerical markers as values.
Fields with identical markers greater or equal than C<0> will have
identical content, fields with identical markers littler than C<0>
are not allowed to be identical.

A following array reference of fields is not allowed.
After the join table array ref, the optional hash
ref with conditions and restrictions and an optional
callback have to follow immediately.

B<Joins are EXPERIMENTAL and may change without warnings.>

=head3 Treatments

Sometimes field functions and returned values shall be treated
in a special way.
By handing over subroutines, C<select> as well as C<load> allow
for these treatments.

  my $name = sub {
    return ('name', sub { uc $_[0] });
  };
  $oro->select(Person => ['age', [ $name => 'name'] ]);

This example returns all values in the 'name' column in uppercase.
Treatments are array refs in the field array, with the first
element being a treatment subroutine ref and the second element
being the alias of the column.

The treatment subroutine returns a field value (an SQL string),
optionally an anonymous subroutine that is executed after each
returned value, and optionally an array of values to pass to the inner
subroutine. The first parameter the inner subroutine has to handle,
is the value to treat, following the optional treatment parameters.
The treatment returns the treated value (that does not has to be a string).

Outer subroutines are executed as long as the first value is not a string
value. The only parameter passed to the outer subroutine is the
current table name.

See L<DBIx::Oro::Driver::SQLite> for examples of treatments.

B<Treatments are EXPERIMENTAL and may change without warnings.>


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
        chi        => CHI->new(),
        key        => 'all_persons',
        expires_in => '10 min'
      }
    }
  );

Selected results can be directly cached by using the C<-cache>
keyword. It accepts a hash ref with the parameter C<chi>
containing the cache object and C<key> containing the key
for caching. If no key is given, the SQL statement is used
as the key. All other parameters are transferred to the C<set>
method of the cache.

B<Note:> Although the parameter is called C<chi>, all caching
objects granting the limited functionalities of C<set> and C<get>
methods are valid (e.g., L<Cache::Cache>, L<Mojo::Cache>).

B<Caching is EXPERIMENTAL and may change without warnings.>


=head2 C<load>

  my $user  = $oro->load(Person, { id => 4 });
  my $user  = $oro->load(Person, ['name'], { id => 4 });
  my $count = $oro->load(Person, ['count(*):persons']);

Returns a single hash ref of a given table,
that meets a given condition.
Expects the table name of selection, an optional array ref of fields
to return and a hash ref with conditions, the rows have to fulfill.
Normally this includes the primary key.
Restrictions as well as the caching systems can be applied as with
L<select>.
In case of scalar values, identity is tested.
In case of array refs, it is tested, if the field is an element of the set.
Fields can be column names or functions. With a colon you can define
aliases for the field names.


=head2 C<count>

  my $persons = $oro->count('Person');
  my $pauls   = $oro->count('Person' => { name => 'Paul' });

Returns the number of rows of a table.
Expects the table name and a hash ref with conditions,
the rows have to fulfill.
Caching can be applied as with L<select>.


=head2 C<delete>

  my $rows = $oro->delete(Person => { id => 4 });

Deletes rows of a given table, that meet a given condition.
Expects the table name of selection and optionally a hash ref
with conditions and restrictions, the rows have to fulfill.
In case of scalar values, identity is tested for the condition.
In case of array refs, it is tested, if the field is an element of the set.
Restrictions can be applied as with L<select>.
Returns the number of rows that were deleted.


=head2 C<table>

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

Returns a new C<DBIx::Oro> object with a predefined table
or joined tables. Allows to omit the first table argument for the methods
L<select>, L<load>, L<count> and - in case of non-joined-tables -
for L<insert>, L<update>, L<merge>, and L<delete>.
C<table> in conjunction with a joined table can be seen as an "ad hoc view".

B<This method is EXPERIMENTAL and may change without warnings.>


=head2 C<txn>

  $oro->txn(
    sub {
      foreach (1..100) {
        $oro->insert(Person => { name => 'Peter'.$_ }) or return -1;
      };
      $oro->delete(Person => { id => 400 });

      $oro->txn(
        sub {
          $oro->insert('Person' => { name => 'Fry' }) or return -1;
        }) or return -1;
    });

Allows to wrap transactions.
Expects an anonymous subroutine containing all actions.
If the subroutine returns -1, the transactional data will be omitted.
Otherwise the actions will be released.
Transactions established with this method can be securely nested
(although inner transactions may not be true transactions depending
on the driver).


=head2 C<import_sql>

  my $oro = DBIx::Oro->new(
    driver => 'SQLite',
    file   => ':memory:,
    import => ['myschema.sql', 'mydata.sql']
  );

  $oro->import_sql('mydb.sql');
  $oro->import_sql(qw/myschema.sql mydata.sql/);
  $oro->import_sql(['myschema.sql', 'mydata.sql']);

Loads a single or multiple SQL documents (utf-8) and applies
all statements sequentially. Each statement has to be delimited
using one comment line starting with C<-- ->.

B<This method is EXPERIMENTAL and may change without warnings.>


=head2 C<do>

  $oro->do(
    'CREATE TABLE Person (
        id   INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
     )');

Executes SQL code.
This is a wrapper for the DBI C<do()> method (but fork- and thread-safe).


=head2 C<explain>

  print $oro->explain(
    'SELECT ? FROM Person', ['name']
  );

Returns the query plan for a given query as a line-breaked string.

B<This method is EXPERIMENTAL and may change without warnings.>


=head2 C<prep_and_exec>

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

=head2 C<on_connect>

  $oro->on_connect(
    sub { $log->debug('New connection established') }
  );

  if ($oro->on_connect(
    my_event => sub {
      shift->insert(Log => { msg => 'reconnect' } )
    })) {
    say 'Event newly established!';
  };

Add a callback for execution in case of newly established
database connections.
The first argument to the anonymous subroutine is the Oro object,
the second one is the newly established database connection.
Prepending a string with a name will prevent from adding an
event multiple times - adding the event again will be ignored.
Returns a true value in case the event is newly established,
otherwise false.
Events will be emitted in an unparticular order.

B<This event is EXPERIMENTAL and may change without warnings.>


=head1 DEPENDENCIES

L<Carp>,
L<DBI>,
L<DBD::SQLite>,
L<File::Path>,
L<File::Basename>.


=head1 ACKNOWLEDGEMENT

Partly inspired by L<ORLite>, written by Adam Kennedy.
Some code is based on L<DBIx::Connector>, written by David E. Wheeler.
Without me knowing (it's a shame!), some of the concepts are quite similar
to L<SQL::Abstract>, written by Nathan Wiger et al.


=head1 AVAILABILITY

  https://github.com/Akron/DBIx-Oro


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut

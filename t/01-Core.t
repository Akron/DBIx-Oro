use Test::More;
use File::Temp qw/:POSIX/;
use Data::Dumper 'Dumper';
use strict;
use warnings;

plan tests => 83;


$|++;


use lib 'lib', '../lib', '../../lib';
use_ok 'DBIx::Oro';

my $_init_name =
'CREATE TABLE Name (
   id       INTEGER PRIMARY KEY,
   prename  TEXT NOT NULL,
   surname  TEXT
 )';

my $_init_content =
'CREATE TABLE Content (
   id         INTEGER PRIMARY KEY,
   content    TEXT,
   title      TEXT,
   author_id  INTEGER
 )';

my $_init_book =
'CREATE TABLE Book (
   id         INTEGER PRIMARY KEY,
   title      TEXT,
   year       INTEGER,
   author_id  INTEGER,
   FOREIGN KEY (author_id) REFERENCES Name(id)
)';

# Real DB:
my $db_file = tmpnam();

ok(my $oro = DBIx::Oro->new(
  $db_file => sub {
    for ($_[0]) {
      $_->do($_init_name);
      $_->do($_init_content);
      $_->do($_init_book);
    };
  }), 'Init real db');

ok($oro->insert(Content => {
  title => 'Test',
  content => 'Value 1'
}), 'Before disconnect');

ok($oro->dbh->disconnect, 'Disonnect');

# Driver test
is($oro->driver, 'SQLite', 'Driver');

ok($oro->insert(Content => {
  title => 'Test', content => 'Value 2'
}), 'Reconnect');

ok($oro->on_connect(
  sub {
    ok(1, 'on_connect release 1')}
), 'on_connect');

ok($oro->on_connect(
  testvalue => sub {
    ok(1, 'on_connect release 2')}
), 'on_connect');

ok(!$oro->on_connect(
  testvalue => sub {
    ok(0, 'on_connect release 3')}
), 'on_connect');

ok($oro->dbh->disconnect, 'Disconnect');

ok($oro->insert(Content => {
  title => 'Test', content => 'Value 3'
}), 'Reconnect');

$db_file = '';

ok($oro = DBIx::Oro->new( $db_file ), 'Init temp db');

my ($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql, 'No last SQL');
ok(!$last_sql_cache, 'No Cache');

$oro->txn(
  sub {
    for ($_[0]) {
      $_->do($_init_name);
      $_->do($_init_content);
      $_->do($_init_book);
    }
  });


ok($oro->insert(Content => {
  title => 'Test', content => 'Value 1'
}), 'Before disconnect');

ok($oro->dbh->disconnect, 'Disonnect');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->insert(Content => {
    title => 'Test', content => 'Value 2'
  }), 'Reconnect');
};

# In memory db
$db_file = ':memory:';

ok($oro = DBIx::Oro->new(
  $db_file => sub {
    for ($_[0]) {
      $_->do($_init_name);
      $_->do($_init_content);
      $_->do($_init_book);
    };
  }), 'Init memory db');

{
  local $SIG{__WARN__} = sub {};

  # Negative checks
  ok($oro->insert(Content => { title => 'Check!',
			       content => 'This is content.'}), 'Insert');

  ok($oro->insert(Name => { prename => 'Akron',
			    surname => 'Sojolicious'}), 'Insert');

  ok(!$oro->insert(Content_unknown => {title => 'Hey!'}), 'Insert');

  ok(!$oro->insert(Name => { surname => 'Rodriguez'}), 'Insert');

  ok(!$oro->update(Content_unknown =>
		     { content => 'This is changed content.' } =>
		       { title => 'Check not existent!' }), 'Update');

  ok(!$oro->update(Content =>
		     { content_unkown => 'This is changed content.' } =>
		       { title => 'Check not existent!' }), 'Update');

  ok(!$oro->select('Content_2'), 'Select');

  ok(!$oro->merge( Content_unknown =>
		     { content => 'Das ist der fuenfte content.' } =>
		       { 'title' => 'Noch ein Check!' }),
     'Merge');

  ok(!$oro->insert(Content => [qw/titles content/] =>
		     ['CheckBulk','Das ist der elfte content']),
     'Bulk Insert');

  ok(!$oro->insert(Content => [qw/title content/] =>
		     ['CheckBulk','Das ist der zwoelfte content', 'Yeah']),
     'Bulk Insert');

  ok(!$oro->insert(Content => [qw/title content/]), 'Bulk Insert');
};

$oro->insert(Name => { prename => '0045', surname => 'xyz777'});

is($oro->load(Name => { surname => 'xyz777' })->{prename},
   '0045',
   'Prepended Zeros');

$oro = DBIx::Oro->new(
  $db_file => sub {
    shift->do($_init_name);
  });

ok($oro, 'Created');
ok($oro->created, 'Created');

if ($oro->created) {
  $oro->do($_init_content);
  $oro->do($_init_book);
  $oro->do('CREATE INDEX i ON Book(author_id)');
};


# Insert:
ok($oro->insert(Content => { title => 'Check!',
			     content => 'This is content.'}), 'Insert');

ok($oro->insert(Name => { prename => 'Akron',
			  surname => 'Sojolicious'}), 'Insert');

# Update:
ok($oro->update(Content =>
		  { content => 'This is changed content.' } =>
		    { title => 'Check!' }), 'Update');

is($oro->last_insert_id, 1, 'Row id');

like($oro->last_sql, qr/^update/i, 'SQL command');
($last_sql, $last_sql_cache) = $oro->last_sql;
ok(!$last_sql_cache, 'No Cache');

ok(!$oro->update(Content =>
		  { content => 'This is changed content.' } =>
		    { title => 'Check not existent!' }), 'Update');

# Load:
my $row;
ok($row = $oro->load(Content => { title => 'Check!' }), 'Load');

is ($row->{content}, 'This is changed content.', 'Load');

ok($oro->insert(Content =>
		  { title => 'Another check!',
		    content => 'This is second content.' }), 'Insert');

ok($oro->insert(Content =>
		  { title => 'Check!',
		    content => 'This is third content.' }), 'Insert');

my $array;
ok($array = $oro->select(Content => { title => 'Check!' }), 'Select');
is($array->[0]->{content}, 'This is changed content.', 'Select');
is($array->[1]->{content}, 'This is third content.', 'Select');

ok($row = $oro->load(Content => { title => 'Another check!' } ), 'Load');
is($row->{content}, 'This is second content.', 'Check');

is($oro->delete(Content => { title => 'Another check!' }), 1, 'Delete');
ok(!$oro->delete(Content => { title => 'Well.' }), 'Delete');

$oro->select('Content' => sub {
	       like(shift->{content},
		    qr/This is (?:changed|third) content\./,
		    'Select');
	     });

my $once = 1;
$oro->select('Content' => sub {
	       ok($once--, 'Select Once');
	       like(shift->{content},
		    qr/This is (?:changed|third) content\./,
		    'Select Once');
	       return -1;
	     });

$oro->select('Name' => ['prename'] =>
	       sub {
		 ok(!exists $_[0]->{surname}, 'Fields');
		 ok($_[0]->{prename}, 'Fields');
	     });

ok($oro->update( Content =>
		   { content => 'Das ist der vierte content.' } =>
		     { 'title' => 'Check!' }), # Changes two entries!
   'Merge');

ok($oro->merge( Content =>
		  { content => 'Das ist der fuenfte content.' } =>
		    { 'title' => 'Noch ein Check!' }),
   'Merge');

ok($oro->merge( Content =>
		  { content => 'Das ist der sechste content.' } =>
		    { 'title' => ['Noch ein Check!', 'FooBar'] }),
   'Merge');

is($oro->select('Content' =>
		  { content => 'Das ist der sechste content.'}
		)->[0]->{title}, 'Noch ein Check!', 'Title');

ok($oro->merge( Content =>
		  { content => 'Das ist der siebte content.' } =>
		    { 'title' => ['HelloWorld', 'FooBar'] }),
   'Merge');

ok(!$oro->select('Content' =>
		   { content => 'Das ist der siebte content.'}
		 )->[0]->{title}, 'Title');


ok($oro->delete('Content' => { content => ['Das ist der siebte content.']}),
   'Delete');

is($oro->last_insert_id, 5, 'Row id');

ok($oro->insert(Content => [qw/title content/] =>
	   ['CheckBulk','Das ist der sechste content'],
	   ['CheckBulk','Das ist der siebte content'],
	   ['CheckBulk','Das ist der achte content'],
	   ['CheckBulk','Das ist der neunte content'],
	   ['CheckBulk','Das ist der zehnte content']), 'Bulk Insert');

ok($array = $oro->select('Content' => [qw/title content/]), 'Select');
is(@$array, 8, 'Check Select');

ok($array = $oro->load('Content' => {content => 'Das ist der achte content'}), 'Load');
is($array->{title}, 'CheckBulk', 'Check Select');

ok($oro->delete('Content', { title => 'CheckBulk'}), 'Delete Table');

ok($array = $oro->select('Content' => [qw/title content/]), 'Select');
is(@$array, 3, 'Check Select');

ok($array = $oro->select('Content' => ['id'] => { id => [1..4] }), 'Select');
is('134', join('', map($_->{id}, @$array)), 'Where In');


# Count
ok(!$oro->count(
  Name =>
    ['prename'] => {
      prename => 'Sabine'
    }), 'Ignore fields in Count');



# Reformatting SQL
$oro->select(Name => {
  prename => [
    qw/Sabine Margot Peter Heinrich Wilhelm Kevin Schorsch/
  ],
  surname => [
    qw/Meier Michels Petermann Kocholski/
  ]});

like($oro->last_sql, qr/4 x \?/, 'Reformatted last_sql');
like($oro->last_sql, qr/7 x \?/, 'Reformatted last_sql');

$oro->insert(
  Name =>
    [qw/prename surname/] => (
      [qw/John Major/],
      [qw/Katharina Valente/],
      [qw/Sergei Prokofjew/],
      [qw/David Suchet/]
    ));

like($oro->last_sql, qr/WITH 4 x UNION SELECT/, 'Reformatted last_sql');

ok($oro->do(
  'CREATE TABLE KeyCollection (
     id   INTEGER PRIMARY KEY,
     key1 INTEGER,
     key2 INTEGER,
     key3 INTEGER,
     key4 INTEGER,
     key5 INTEGER,
     key6 INTEGER
  )'), 'Create Table');

ok($oro->insert(
  KeyCollection =>
    [map {'key' . $_} (1..6) ] =>
      [map {'a_' . $_} (1..6) ],
      [map {'b_' . $_} (1..6) ],
      [map {'c_' . $_} (1..6) ],
      [map {'d_' . $_} (1..6) ],
      [map {'e_' . $_} (1..6) ],
      [map {'f_' . $_} (1..6) ],
      [map {'g_' . $_} (1..6) ],
      [map {'h_' . $_} (1..6) ],
  ), 'Bulk Insert');

like($oro->last_sql, qr/WITH 8 x UNION SELECT 6 x \?/, 'Reformatted last_sql');


1;

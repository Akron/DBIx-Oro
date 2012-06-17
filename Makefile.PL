#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    VERSION_FROM => 'lib/DBIx/Oro.pm',
    NAME         => 'DBIx-Oro',
    AUTHOR       => 'Nils Diewald',
    PREREQ_PM => {
        'DBD::SQLite'  => 1.33,
        'DBI'          => 1.57,
	'File::Temp'   => 0.20,
	'Data::Dumper' => 0,
	'Carp'         => 0,
	'strict'       => 0,
	'warnings'     => 0,
	'utf8'         => 0,
	'bytes'        => 0,
	'Math::BigInt' => 0
    },
    test => {
      TESTS => 't/*.t'
    }
);

#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'DBIx::Oro',
  AUTHOR       => 'Nils Diewald',
  ABSTRACT     => 'Simple Relational Database Accessor',
  VERSION_FROM => 'lib/DBIx/Oro.pm',
  BUILD_REQUIRES => {
    'Test::More'   => 0,
    'Math::BigInt' => 0,
    'Data::Dumper' => 0
  },
  PREREQ_PM => {
    'DBD::SQLite'  => 1.33,
    'DBI'          => 1.57,
    'File::Temp'   => 0.20,
    'Carp'         => 0,
    'strict'       => 0,
    'warnings'     => 0,
    'utf8'         => 0,
    'bytes'        => 0
  },
  LICENSE      => 'perl',
  META_MERGE   => {
    requires  => { perl => '5.010001' },
    resources => {
      license     => 'http://www.opensource.org/licenses/artistic-license-2.0',
      repository  => 'https://github.com/Akron/DBIx-Oro'
    }
  },
  MIN_PERL_VERSION => '5.010001',
  test => {
    TESTS => 't/*.t t/SQLite/*.t'
  }
);

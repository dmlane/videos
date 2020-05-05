#!/usr/bin/env bash

perl_dependencies="
DBI
Clipboard
TAP::Harness::Env
Const::Fast
File::Basename
MP4::Info 
Term::Screen 
DBD::SQLite
Term::ReadKey
"

for pkg in $perl_dependencies
do
	perldoc -l $pkg >/dev/null && continue
	cpan install $pkg 
done

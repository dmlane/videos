#!/usr/bin/env bash

perl_dependencies="
DBI
File::Basename
MP4::Info 
Switch
Term::Menus 
Term::ReadKey
"

for pkg in $perl_dependencies
do
	perldoc -l $pkg >/dev/null && continue
	cpan install $pkg
done

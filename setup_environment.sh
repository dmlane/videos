#!/usr/bin/env bash

function install_module {
	perldoc -l $1 >/dev/null
	if [ $? -eq 0 ] ; then
		echo $1 already installed
		return
	fi
	/usr/local/bin/cpan install $1
	if [ $? -ne 0 ] ; then
		echo "Failed to install $1 - aborting"
		exit 1
	fi
}

if [ ! -f /usr/local/bin/perl ] ; then
	brew install perl
fi

if [ ! -f /usr/local/opt/mysql-client/bin/mysql ] ; then
	brew install mysql-client 
	brew link --force mysql-client
fi

perldoc -l local::lib
if [ $? -ne 0 ] ; then
	PERL_MM_OPT="INSTALL_BASE=$HOME/perl5" cpan local::lib
	echo 'eval "$(perl -I$HOME/perl5/lib/perl5 -Mlocal::lib=$HOME/perl5)"'>>~/.bashrc
	. ~/.bashrc
fi

install_module DBI

perldoc -l DBD:MariaDB 
if [ $? -ne 0 ] ; then
	export LDFLAGS="-L/usr/local/opt/mysql-client/lib"
	export CPPFLAGS="-I/usr/local/opt/mysql-client/include/mysql"
	export DBD_MARIADB_CFLAGS=-I/usr/local/mysql/include/mysql
	export DBD_MARIADB_LIBS="-L/usr/local/mysql/lib/mysql -lmysqlclient"
	#export DBD_MARIADB_CONFIG=mysql_config
	export DBD_MARIADB_TESTDB=test
	export DBD_MARIADB_TESTHOST=192.168.199.210
	export DBD_MARIADB_TESTPORT=3307
	export DBD_MARIADB_TESTUSER=test_user
	export DBD_MARIADB_TESTPASSWORD="test=12345A"
	cpan install DBD::MariaDB
	if [ $? -ne 0 ] ; then
		echo "Failed to install $1 - aborting"
		exit 1
	fi
fi
install_module Clipboard
install_module MP4::Info
install_module Term::ReadKey
install_module Const::Fast
install_module Term::Screen
install_module Perl::Tidy

exit
	
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

#!/usr/bin/env bash

# Portable way to get real path .......
readlinkf(){ perl -MCwd -e 'print Cwd::abs_path shift' "$1";}

fail() { echo "$1"; exit 1;}
macos() { test $(uname -s) == Darwin;}
function apt_install {
	if [ ! -z "$2" ] ; then
		test -f $2 && return
	fi
	echo "Installing $1"
	sleep 1
	sudo apt -y install $1
}
function brew_install {
	if [ ! -z "$2" ] ; then
		test -f $2 && return
	fi
	echo "Installing $1"
	sleep 1
	brew install $1
	test "$3" = "link" && brew link $1 --force
	
}
function linux_packages {
	#apt_install vim /usr/bin/vim
	:
}
function mac_packages {
	test -f /usr/local/bin/brew ||\
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
	brew_install mysql-client /usr/local/bin/mysql link

}

function perl_install {
	perldoc -l $1 >/dev/null 2>&1
	test $? -eq 0 && return
	echo "Installing perl module $1"
	cpanm $1
}
	
myscript="$(readlinkf $0)"
bindir=$(dirname $myscript)
envdir=${bindir%/bin}/env

if macos ; then
	mac_packages
else
	linux_packages
fi

#-------------------------------------------------------------------------
perl_install DBI
perl_install MP4::Info
perl_install Clipboard
perl_install Const::Fast
perl_install Term::Screen
perl_install DBD::MariaDB
mkdir -pv ~/data

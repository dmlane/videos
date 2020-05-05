#!/bin/bash

export PERL5LIB="/Users/dave/Komodo-PerlRemoteDebugging-12.0.1-91869-macosx:$PERL5LIB"
export PERLDB_OPTS="RemotePort=127.0.0.1:9000"
#export PERLDB_OPTS="RemotePort=192.168.199.42:9000"
export DBGP_IDEKEY="dave"

perl -d $1

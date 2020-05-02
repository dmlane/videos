#!/bin/bash

export PERL5LIB="/System/Volumes/Data/Applications/Komodo IDE 12.app/Contents/SharedSupport/dbgp/perllib:$PERL5LIB"
export PERLDB_OPTS="RemotePort=127.0.0.1:9000"
export DBGP_IDEKEY="dave"

perl -d $1

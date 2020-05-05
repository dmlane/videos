#!/bin/bash

export PERL5LIB="${HOME}/Komodo.debug/perllib"
export PERLDB_OPTS="RemotePort=127.0.0.1:9000"
export DBGP_IDEKEY="dave"

perl -d $1

#!/usr/bin/env bash

projectdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

rlwrap --history-filename "$projectdir/.rlhistory" telnet 127.0.0.1 4242

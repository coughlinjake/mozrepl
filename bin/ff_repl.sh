#!/usr/bin/env bash

echo "$0 is currently DISABLED!"
echo ""
echo "It's intent is to provide an easy way to start Firefox with the REPL profile."
echo "However, I now start the Firefox MozRepl extension in ALL my profiles."
echo "Consequently, this script isn't needed at the moment."
exit 1

projectdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

shopt -s nocasematch

# for i in _dump.log _output.log _telnet_dump.log _repl_output.log failure_log.log runlog.log runlog.tclog
# do
#     if [[ -f "$projectdir/$i" ]]; then
#         rm -f "$projectdir/$i"
#     fi
# done

# on BigMac, Firefox needs to be started with the repl profile.
# on Plato, the default Firefox profile provides the REPL.
ff_args=( -no-remote )
if [[ "$HOSTNAME" =~ "bigmac" ]]; then
    ff_args=( ${ff_args[@]-} -P repl )
fi

/Applications/Firefox.app/Contents/MacOS/firefox-bin ${ff_args[@]} &>/dev/null </dev/null &

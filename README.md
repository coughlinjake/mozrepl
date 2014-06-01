# MozRepl

The mozrepl gem absolutely requires that the MozRepl Firefox extension be configured to load
the `REPL.js` during initialization.

Verify that in the Firefox profile, the file `prefs.js` contains the following:

    user_pref("extensions.mozrepl.initUrl", "file://localhost/Users/jakec/UNISON/src/ruby/jobmgr/init.js");


level: minor

The kitchen now cleans up after itself. A cook registers any dev server, watcher, tunnel or poll it
starts (`kitchen.sh procs --add <pid> "<what>"`) and stops it before the handoff; the sous reaps
what is left after the merge, and `bk stop` reaps every station before it pauses. The reap kills only
a registered process that is still the same one (same start time and command line), never a
`claude`, `tmux` or shell session, a system process, or anything nobody registered. `kitchen.sh
procs --scan` lists unregistered processes standing in a station (it only reports) and the board
counts them. Handoffs carry a "Processes" line. You don't need to do anything: cooks and the sous
pick the rule up from the plugin.

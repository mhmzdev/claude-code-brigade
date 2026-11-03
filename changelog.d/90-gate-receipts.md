level: minor

Every run of the check now leaves a receipt in the station's check log: which tree, which command, how it ended, and a digest of what it printed. The taster reads the receipt instead of running the check, and `open-pr` will not push a tree without a green one. For you, nothing to set up: a cook's last act before `[handoff]` is now `kitchen.sh check`, so the taster has a receipt for the exact tree it reads. One bug fixed on the way: the check could name the wrong tree when a file was edited to the same size within a second of the index being written.

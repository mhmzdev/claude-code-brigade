level: patch

The test suite now runs green from inside a kitchen (a session `bk open` started): it no longer
picks up `bk`'s launch flags or tmux's variables, and its Window test asks the OS for a free port,
so two stations' checks at once don't collide. You don't need to run the gate with `env -u …` any
more. Nothing else changes for you.

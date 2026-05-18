# Syntax

Symbols:

```txt
$ = root/local context data
@ = remote file/location context
# = remote SSH execution context
```

Main block form:

```txt
for_each ${selector}
| <subject> <verb> <args...>
```

Examples:

```txt
for_each ${topology.shards[*]}
| @${host}:${install.dir}/datadir/archive send ${resources.replayJar}
| #${host}:${install.dir}/datadir/archive run ${java} -jar replay.jar
```

Selectors planned for v1:

```txt
${topology.shards[*]}              all map values or array items
${topology.shards[shard3]}         one map value, treated as a one-item loop
${topology.shards[*].hosts[*]}     flattened traversal, replacing nested loops
```

No comma selectors in v1. Users can copy/paste blocks for a few specific shards.

Comments use `//` so `#` stays available for remote execution subjects.

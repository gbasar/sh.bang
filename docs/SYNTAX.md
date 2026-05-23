# Syntax

Symbols:

```txt
@ = remote host context (implicit SSH hop from current context)
# = reserved — future use
$ = reserved — local machine, future use
```

Main block form:

```txt
for_each ${selector}
| <subject> <verb> <args...>
```

## Subject and path

The `:path` in a subject is the **implicit working directory** — the engine `cd`s there
before running any command. The playbook author never writes `cd`.

```txt
@${host}:${install.dir}   ssh to host, cd to install.dir, run commands there
```

## Execution model

All pipes are one-shot under the hood — each command is dispatched independently,
not as part of a persistent shell session. The `:path` handles the working directory
implicitly, which covers most cases where shared state would otherwise be needed.

For nested hops, the engine builds a chain from the `for_each` nesting depth.
The default implementation uses `ssh -J` (ProxyJump), but this is a **swappable
strategy** — SSH policies in many environments block `-J`, and the engine is designed
so the hop mechanism can be replaced without changing the playbook syntax or the
rest of the framework.

## Nested for_each — walking the network path

Nesting `for_each` blocks mirrors nesting in the topology. Each level is an implicit
SSH hop **from the previous context**, not from the control host.

The inner `for_each` is a pipe in the outer block — indentation is **meaningful**,
not decorative. Commands before the inner `for_each` run at the outer hop; indented
pipes inside run at the inner hop.

```txt
for_each ${trading.shard[*]}
| @${primary.host}:${install.directory} run some-setup.sh
| for_each ${dr.host}
  | @${dr.host}:${install.directory} run java -jar replay.jar
```

Step 1: SSH from your PC to the shard host (outer for_each)
Step 2: run some-setup.sh there
Step 3: hop from the shard host onward to dr.host (inner for_each)
Step 4: run replay.jar there

If dr.host is behind a firewall unreachable from your PC, this just works —
because the inner hop originates from inside the shard host, not from your PC.
No jump host config. No special syntax. The playbook structure *is* the network path.

## Selectors

```txt
${topology.shards[*]}              all map values or array items
${topology.shards[shard3]}         one map value, treated as a one-item loop
${topology.shards[*].hosts[*]}     flattened traversal, replacing nested loops
```

No comma selectors in v1. Users can copy/paste blocks for a few specific shards.

Comments use `//` so `#` stays available as a reserved symbol.

## Examples

```txt
// Replay on shard3 primary
for_each ${trading.shard[shard3]}
| @${primary.host}:${install.directory} run java -jar replay.jar


// Replay on dr host (behind firewall — walk the path)
for_each ${trading.shard[*]}
| for_each ${dr.host}
  | @${dr.host}:${install.directory} run java -jar replay.jar
```

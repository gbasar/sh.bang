# sh.bang Design

`sh.bang` is a Bash + jq runbook runner.

Core rule:

```txt
jq owns the tree.
Bash executes the leaves.
```

Human-authored playbooks use `.shbang` text because JSON is poor for multiline command blocks.

Data boundaries:

- JSON holds context, resources, and verb registries.
- HOCON is allowed as an input resource and later converted/rendered to JSON.
- After conversion, HOCON data is just another context node.
- `.shbang` files reference context nodes with `${...}`.

The control environment should be modern:

- Bash >= 5.1
- jq >= 1.6

Remote hosts may be older. They are SSH targets and only need the shell/tooling required by the selected verb. Verb metadata can later declare compatibility such as `posix`, `bash4`, or `bash5`.

Remote meanings:

```txt
@host:/path  remote file/location context
#host:/path  remote SSH execution context
```

Users should not write `ssh`, `scp`, or `cd` in normal playbooks.

## HOCON context formats

Real-world deployments often have different HOCON structures across environments
(prod vs SIT). sh.bang handles this transparently — the playbook never changes,
only the context file passed at runtime.

The HOCON self-reference alias is the trick that makes this work:

```hocon
// SIT format — numbered instances, aliased so selector still works
trading {
  shard = ${trading.instances}
  instances { 1 { ... } 2 { ... } }
}

// Prod format — named shards directly
trading {
  shard { 4 { ... } dr { ... } }
}
```

After HOCON → JSON conversion, both expose `trading.shard[*]` — the same selector
works against both. See `examples/replay/trading1.hocon` (prod) and
`examples/replay/trading2.hocon` (SIT) as reference.

## Routing And Events

The runner should feel like a small command router, not a pile of inline Bash branches.

Flow:

```txt
parse CLI into runtime
parse playbook into command/event objects
submit objects to router
router checks dry-run, verbosity, compatibility, and handlers
handlers write console output or file records
```

Initial event handlers:

```txt
console  human-readable output to stderr/stdout for interactive use
file     JSONL event records appended to a file
```

Command code should emit events and let handlers decide how to display or record them. Later execution should route every command through one place so dry-run can skip the dangerous part without duplicating checks throughout the code.

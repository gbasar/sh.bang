# POC Scope

First implementation:

- Parse `for_each` blocks.
- Parse `|` body commands.
- Support `-v`, `-vv`, `-vvv`, and `-vvvv` logging.
- Load help and flag meaning from `spec/cli.json`.
- Route commands through an associative-array command table.
- Route global and run flags through handler tables, not `case`.
- Emit parser output through an event bus.
- Provide `console` and `file` event handler scaffolding.
- Provide a small test harness.
- Produce dry-run parse output.

Next implementation steps:

- Convert selectors to jq.
- Expand current items from context.
- Render `${...}` placeholders.
- Dispatch `@` subjects to file operations.
- Dispatch `#` subjects to remote execution.
- Resolve JSON-defined verbs such as `list`.

Explicitly out of scope for the first code step:

- SSH/SCP execution.
- HOCON conversion.
- Parallel execution.
- Run records.
- Smart archive unpacking.
- Plugin system.

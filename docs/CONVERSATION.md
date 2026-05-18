# Conversation Notes

The project started as a Bash-only automation idea and narrowed into a small runbook runner for replay workflows across shard/server topology.

Important decisions:

- Name: `sh.bang`.
- Use Bash + jq only as baseline assumptions.
- Use modern Bash in the control environment.
- Do not expose jq to users.
- Do not write playbooks in JSON; use readable `.shbang` text.
- Keep JSON for context, resources, and verb definitions.
- Treat HOCON as an input/resource format that becomes JSON context.
- Use `@` for remote file/location operations.
- Use `#` for remote SSH execution operations.
- Use `${...}` to avoid ambiguity between variables and filesystem paths.
- Use one `for_each` primitive; selectors such as `${topology.shards[*].hosts[*]}` can flatten nested data instead of adding nested loop syntax.
- Verbs should become JSON-defined over time so teams can fetch verb packs as resources.
- The first code step should prove parser shape, logging, tests, and examples without running remote commands.
- The user was disappointed by case-heavy Bash and wants table/spec-driven flow.
- The code should be readable to a Java programmer who hates Bash programming.
- Use jq when one query replaces 20-30 shell lines, but hide jq behind named helpers.
- Use a router/runtime object so dry-run, verbosity, logging, and later error handling are centralized.
- Add an event model: code emits events, active handlers such as `console` and `file` decide what to do.

Future ideas:

- Per-verb dry-run metadata.
- Run records under `.shbang-runs/`.
- Parallel execution with Bash `wait -n`.
- Remote compatibility tags such as `posix`, `bash4`, and `bash5`.
- UBI 9 minimal container as a final control-environment test.

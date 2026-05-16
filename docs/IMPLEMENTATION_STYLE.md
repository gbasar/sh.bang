# Implementation Style

`sh.bang` uses modern Bash in the control environment.

Requirements:

- Bash >= 5.1
- jq >= 1.6

Function I/O rules:

- Scalar return values are printed to stdout.
- Structured outputs use nameref maps or arrays.
- Success/failure is reported by exit code.
- Logs go to stderr.
- Nested data stays in JSON and is queried with jq.
- Avoid mutable globals except readonly constants and explicit registries.

Preferred Bash features:

- `declare -A` associative arrays for records and dispatch tables.
- `local -n` namerefs for output maps/arrays.
- Indexed arrays for argv.
- `mapfile` for small streams when useful.
- `[[ ... =~ ... ]]` for parser shell syntax.
- JSON plus jq for CLI/help metadata where it keeps policy out of Bash.
- Associative-array routing tables instead of `case` dispatch.
- A runtime map passed through routers, parser, and later executors.
- Events for console/file output instead of scattered logging decisions.

Avoid old positional-heavy style except for tiny functions with one or two obvious inputs.

The CLI uses a runtime map passed through the command router. Handlers should inspect runtime state such as `dry_run` and `verbosity` instead of reading scattered globals.

The user preference is explicit: avoid case-heavy Bash. The code should be followable for a Java programmer who dislikes Bash programming. Use named helpers, data tables, and jq where one jq query replaces a large amount of shell branching.

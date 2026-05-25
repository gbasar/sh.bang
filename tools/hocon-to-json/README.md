# hocon-to-json

Converts a HOCON (Human-Optimized Config Object Notation) file to compact JSON on
stdout. Used by sh.bang's context resolution pipeline so playbooks can be written in
HOCON (comments, includes, substitutions) and passed to `jq` at runtime.

## What it does

- Parses a `.hocon` or `.conf` file using Typesafe Config.
- Resolves `include "other.hocon"` directives **relative to the source file's
  directory** (not the classpath). This allows playbook context files to split
  across a main config and a developer scratch pad in the same directory.
- Outputs compact JSON (`{"key":"value"}`, no whitespace) on stdout.

## Usage

```bash
java -jar hocon-to-json.jar <file.hocon>
```

Output is compact JSON on stdout. Errors (file not found, parse error) go to stderr
with a non-zero exit code.

## HOCON features that work

- Comments (`#` and `//`)
- Substitutions (`${key}`, `${?optional}`)
- Object merging / override
- `include "file.hocon"` resolved relative to the source file

## Example

`environment.conf`:
```hocon
staging {
  jumphost = "trading-host1"
  root     = "/opt/trading"
}
include "developerScratchPad.hocon"
```

`developerScratchPad.hocon` (same directory, gitignored):
```hocon
debug {
  shard     = 1
  class     = OrderEventHandler
  method    = process
  condition = "orderId=ORD-12345"
}
```

```bash
java -jar hocon-to-json.jar environment.conf
# → {"staging":{"jumphost":"trading-host1","root":"/opt/trading"},"debug":{"shard":1,...}}
```

## Build

Requires typesafe-config on the classpath. `lib/ctx.sh` auto-builds the jar if it is
missing, downloading typesafe-config from Maven Central:

```bash
source bin/playground   # sets HOCON_JAR and triggers auto-build if needed
```

Or build manually:
```bash
VERSION=1.4.3
curl -fsSL "https://repo1.maven.org/maven2/com/typesafe/config/${VERSION}/config-${VERSION}.jar" \
     -o /tmp/typesafe-config.jar
javac --release 17 -cp /tmp/typesafe-config.jar \
      tools/hocon-to-json/HoconToJson.java -d /tmp/hocon-build
cd /tmp/hocon-build && jar xf /tmp/typesafe-config.jar
jar cfe tools/hocon-to-json/hocon.jar HoconToJson \
    -C /tmp/hocon-build .
```

Note: the inner class `HoconToJson$1.class` (the anonymous `ConfigIncluder`) must be
included — it is automatically captured when you compile to a directory and jar the
whole directory tree as above.

## sh.bang integration

`lib/ctx.sh` calls this jar automatically when `--ctx` points to a `.hocon` or
`.conf` file:

```bash
./bin/sh.bang run playbook.shbang --ctx examples/debug-replay/environment.conf
```

Set `HOCON_JAR` to override the jar path (default: `/usr/local/lib/hocon.jar`):

```bash
export HOCON_JAR="$REPO/tools/hocon-to-json/hocon.jar"
```

`source bin/playground` sets this automatically.

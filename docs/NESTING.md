# Example: Firewalled DR Hosts

This example shows where sh.bang earns its keep.

## The scenario

You have a trading topology with shards. Each shard has a primary host and a DR host.
The DR hosts are behind a firewall — you cannot reach them directly from your PC.
You must hop through the shard's primary host to get there.

You want to send a replay jar to every DR host.

---

## Option 1: No firewall (direct reach)

If you could reach DR hosts directly, a jq one-liner gets you the hosts:

```bash
jq '.trading.shard | to_entries[] | .value.dr.host' context.json
```

And sure, you could loop over them in two lines of bash:

```bash
for host in $(jq -r '.trading.shard | to_entries[] | .value.dr.host' context.json); do
  scp replay.jar $host:/local/1/trading/shard_dr
done
```

Fine. No argument. But now add variable substitution, dry-run, verbosity, a second hop,
and a second command after the send. Enjoy.

In sh.bang, direct reach looks like this:

```txt
for_each ${trading.shard[*].dr.host}
| @${host}:${dr.directory} send ${resources.replayJar}
```

The selector `${trading.shard[*].dr.host}` flattens the topology and iterates every DR host.
One block. Two lines.

---

## Option 2: Firewalled DR (hop through primary)

DR hosts are only reachable from inside the shard's primary host.
The nested `for_each` walks the network path — each level is an implicit SSH hop
from the previous context, not from your PC.

```txt
for_each ${trading.shard[*]}
| for_each ${dr.host}
  | @${dr.host}:${dr.directory} send ${resources.replayJar}
```

The engine builds `ssh -J primary-host dr-host bash -c "..."` under the hood.
The playbook reads like you're already there.

Now imagine that in two lines of bash. With two hops:

```bash
for shard in $(jq -r '.trading.shard | keys[]' context.json); do
  primary=$(jq -r ".trading.shard.$shard.primary.host" context.json)
  dr=$(jq -r ".trading.shard.$shard.dr.host" context.json)
  ssh $primary ssh $dr bash -c \"cd /local/1/trading/shard_dr && ...\"
done
```

Escaping hell. And that's one hop. Two hops:

```bash
ssh hop1 ssh hop2 ssh dr-host bash -c \"cd ... && ...\"
```

sh.bang at two hops deep:

```txt
for_each ${trading.shard[*]}
| for_each ${zone.jumphost}
  | for_each ${dr.host}
    | @${dr.host}:${dr.directory} send ${resources.replayJar}
```

The structure of the playbook *is* the network path. The engine handles the rest.

---

## Option 3: Depth-first execution order

Nesting isn't just for firewalls. It controls **execution order within each iteration**.

The rule is simple: pipes before a nested `for_each` run first, the nested block runs
next, pipes after it run last. A 15-year-old can figure out how to make primary go last:

```txt
#! Push new version — DR first, primary last

for_each ${trading.shard[*]}
|
| #! DR first (firewalled — hop through primary)
|
| for_each ${dr.host}
| | @${dr.host}:${dr.directory}/app/${appName}/lib send ${resources.replayJar}
| | @${dr.host}:${dr.directory}/app/${appName}/bin run restart.sh
|
| #! Primary and failover last
| #  (DR is already done for this shard — depth-first gives us this for free)
|
| @${primary.host}:${install.directory}/app/${appName}/lib send ${resources.replayJar}
| @${primary.host}:${install.directory}/app/${appName}/bin run restart.sh
| @${failover.host}:${install.directory}/app/${appName}/lib send ${resources.replayJar}
| @${failover.host}:${install.directory}/app/${appName}/bin run restart.sh
```

DR is written first, so it runs first. Primary is written last, so it runs last.
No flags. No modes. No docs to read. The playbook structure *is* the execution order.

In bash, getting this right means carefully structuring nested loops and thinking hard
about ordering. Here you just write it top to bottom the way you'd explain it to a colleague.

---

## The rule

- **Selector can deep-select?** → flat `for_each`, no nesting needed
- **Host behind a firewall?** → nest a `for_each` for each hop, engine builds the `-J` chain
- **Need to control execution order?** → nest a `for_each` block where you want depth-first to kick in

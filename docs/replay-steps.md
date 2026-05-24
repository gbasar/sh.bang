
# Replay Scenario for e2e test.


## 

## Requirements
- end to end tests must pass both variants
1. Sh.Bang exdecuted on git bash (me at my work machine) -> performas actionss on fedora 
2. Sh.Bang executed on servfer fedora -> fedora
## Scenario

- repolay outbound messages on four shards. Shards may share the machine or not.
- 2 shards will be on each host (so in e2e test )
- we need to pass the replay program data from the outbounnd rdat as well as a list of trades we are intested intested\
- that way it only sends the ones we are itneested in

### What this looks like manually

1. Get the replay jar from nexus (resoures)
2. Get the environment.conf from gitlab 
3. get list of trade_id#s we need to trade (local text file)

Begin Loop over host
3. push the replay jar via scp to host /tmp/replay.jar
4. Ssh host
5. mkdir /tmp/replay; mv /tmp/replay.jar  /tmp/replay 
6. mkdir /tmp/replay/shard1, shard1
7. cp $Install.dir/${shard1}/data/(file with yesterday date).tar.gz /tmp/replay/shard1; tar xvf file (cau us same fil mask)
8. repeat for shard2
9. actual replay
10.  Using ${runtme.java.install}/java call replay.jar which will accept as paramter "trad123, trade234..."



### let's discuss this part
### List of trades (Local texe fiel)\
```text
```text
  123_tradeId
  234_tradeId....  about 8 or 10

```
```



```    

```
### Rdat Fles 
  /data/Yesterday'sdata.tar.gz files when unzipped should contain
  - in.dat
  - out.dat (outboaund message log)



```text


```
```
```




```

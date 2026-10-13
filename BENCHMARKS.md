# Load order benchmarks

`bench/bench.luau` times the package the way a tool reaches it: `@load-order` over an `@openmw`
Context for an install the bench writes. The install is four data folders, three masters of
1,001 records and 93 plugins of 101 (statics, lights, people, and cells of six references each),
1.4 MB and 12,396 records in 96 files, and a content list of 103 names, seven of them script
lists. Every plugin
names the three masters in one of three cases, every fourth the plugin before it, and every tenth
a master the order doesn't have. It opens the order whole, cut to two record types, and with
cells cut to their headers; opens a list of entries a third of which don't open; opens a content
list of 512 names no folder has a file of, through a Context that is nothing but that list, which
leaves the package's own work and none of `@tes3`'s or the disk's; finds every plugin's masters
in one list of the order's names, and one plugin's in a list that is another at every call; and
asks for the output folder and for an activation the content already has. Each workload is warmed
up, sized to a batch of about a tenth of a second, and reported as the median of seven batches,
with a full collection between them. Every result is compared with what the writer of the install
says it must be.

`bench/cold.luau` times what one process pays once: the `require` of this package's module with
`@dream/fs` and `@tes3` loaded first, then the first `open` of three plugins and the first
`masters`. Each line is a single sample, so it is run many times and the medians are compared.

```sh
jess run --package jpk/load-order --package jpk/openmw --package-path jpk \
  --capability filesystem.read --capability filesystem.write \
  jpk/load-order/bench/bench.luau <scratch folder> [filter]

jess run --package jpk/load-order --package-path jpk \
  --capability filesystem.read --capability filesystem.write \
  jpk/load-order/bench/cold.luau <scratch folder>
```

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other work while this ran
  (load average 0.8 to 1.1 over the run).
- Date: 2026-10-13.
- Binary: the verified release build of Jess 0.1.0 on l3i 2.0.2 (Luau 0.742), the same one for
  both sides, and the same sibling packages.
- Base: `f1ad870`, the package before the move, with both benches. Head: `5f63aa7`.
- Protocol: the whole of `bench.luau` against an export of base, then head, five times over,
  back to back under one lock; each cell is the median of its five runs. `cold.luau` the same
  way, thirty-one times over. A difference under 5 percent is called no change.

| Workload | Base, µs | Head, µs | Base / head |
|---|---:|---:|---:|
| open: 96 plugins of 103 content files, whole | 1831.8 | 1817.3 | no change |
| open: 96 plugins, the lights and statics of each | 2315.6 | 2275.6 | no change |
| open: 96 plugins, cells without their references | 3093.5 | 3027.7 | no change |
| open: 96 entries given, 32 of them missing, unreadable or not a plugin | 1386.1 | 1374.9 | no change |
| open: a content list of 512 names no folder has, 64 of them script lists | 176.5 | 175.2 | no change |
| masters: each of 96 plugins' in one list of the order's 96 names | 1235.2 | 376.9 | 3.28x |
| masters: one plugin's in a list of 96 names, another list at every call | 25.67 | 27.59 | 0.93x |
| outputDirectory: the folder a generated plugin goes to | 1.508 | 1.504 | no change |
| activate: a name the content already has, in another case | 14.50 | 14.64 | no change |

| One cold process | Base, µs | Head, µs | Base / head |
|---|---:|---:|---:|
| require @dream/fs and @tes3 | 103168.5 | 102953.6 | no change |
| require @load-order, those loaded | 1411.5 | 1585.9 | 0.89x |
| first open, 3 plugins of a content list of 4 | 74.9 | 73.8 | no change |
| first masters, in 3 names | 13.66 | 13.89 | no change |
| require @load-order to the masters | 1502.8 | 1675.4 | 0.90x |

### What moved, and why

One row gained, and none of the gain is the dialect's. `masters` lowered every name of the list
it was handed and keyed a table by it, at every call: 9.6 µs for 96 names, next to the 2.7 µs
`plugin:masters()` takes in `@tes3` for a plugin of four (single runs outside the lock, to say
where to look). A tool asks about each plugin of a load order in turn with the one list
(`merged-lands` does), so an order of 96 plugins lowered 9,216 names to find 314 masters. The
package now keeps a copy of the last list it was asked about and where each of its names is, and
a call first walks the list it is handed against that copy, name for name: about a microsecond
for 96 names when it is the same list, and one comparison when the first name differs. The list
is read at every call as before, so a table changed in place, made again, or handed in another
order answers as it always did; `tests/run.luau` holds that, and the places of a list with a gap.

The same change is the two rows that lost. A caller that hands `masters` another list at every
call pays for the walk and the copy and never uses them: 0.6 µs a call for 96 names (the row is
three calls), 7 percent. No package does that today. And the module takes 0.17 ms longer to
`require` (0.89x), which every process that loads it pays whether it asks for masters or not:
`s3lightfixes` and `tes3merge` never do. Against the 103 ms the modules below it take to load,
that is 0.2 percent of the process; against what it buys, an order of 96 plugins gets 0.86 ms
back from its masters, and a tool that asks about fewer than about twenty plugins of such an
order gets back less than the load cost.

What did not move is where the time is, which is not in this package. Over 96 plugins of 100
records handed in as entries (single runs outside the lock again), opening them is 1.33 ms:
reading the files is 0.52 of it, `tes3.open` framing them 0.57, and the same loop written out by
hand with no package in it 1.26. The package's own work on a file (its loop, the entry it builds,
the reason it words for a file that didn't open) is about 0.7 µs, 5 percent. A filtered open
calls the package once for every record, with one table read in it; the rest of that walk is
`@tes3`'s.

### A change at a time

Each commit against the one before it, on the rows it could touch: five runs warm and thirty-one
cold, alternating, medians.

| Commit | What it does | Row | Before, µs | After, µs | Before / after |
|---|---|---|---:|---:|---:|
| `90d88a1` | an entry's and a master's fields by record pattern | masters, one list | 1261.0 | 1243.3 | no change |
| | | masters, another list at every call | 26.17 | 25.79 | no change |
| | | require @load-order | 1441.3 | 1474.6 | no change (0.98x) |
| `12c973c` | the last list's places kept | masters, one list | 1243.3 | 375.8 | 3.31x |
| | | masters, another list at every call | 25.79 | 28.81 | 0.90x |
| | | require @load-order | 1474.6 | 1681.5 | 0.88x |
| `5f63aa7` | the kept list one `table.clone` | masters, one list | 375.8 | 386.7 | no change |
| | | masters, another list at every call | 28.81 | 27.50 | no change (1.05x) |
| | | require @load-order | 1681.5 | 1677.5 | no change |

`5f63aa7` is at the edge of what this protocol can show: 1.05x here, 1.06x (29.42 against 27.69)
in a run of five before it. It is also four lines shorter.

### The dialect, and what it costs to load

The payload has two dialect constructs, both record patterns: an entry's `name` and `path` in
`open`, and a master's `name` and `size` in `masters`. They are the reads they replace and cost
nothing to load. The bench and the suite build and reduce their lists by comprehension and
reducer.

The one loop of the payload the dialect expresses exactly is the list `masters` returns, and it
stays a loop: as a comprehension it measured the same warm (1271.4 µs against 1265.1 for the
order's masters, 26.11 against 26.12 for the changing list, three runs) and cost 0.11 and 0.15 ms
of `require` in two runs of fifteen (1549.6 against 1441.3, 1536.1 against 1383.8). The others
walk a list a caller hands in (the Context's content, the entries, the names), which may have a
gap that a comprehension would stop at or raise on, or build a map.

A function costs load time by being there, under `--!native`: the same change as two functions
beside `masters` took 0.25 ms of `require`, as one 0.19, and written into `masters` 0.15 (1653.1,
1593.3 and 1561.6 against 1407.1, twenty-one runs). It is one function.

### Measured and left alone

- **An intern pool for the names.** `@dream/intern`'s `ascii-nocase` pool folds the letters
  `string.lower` does here, and answers the same over 23,582 lists a differential run tried,
  odd ones among them, once what isn't a string is sent round it. In place of the lowering it
  made the order's masters 1.24x (1016.7 µs against 1265.1) and, under the kept list, 3.49x
  (362.3). It costs 0.77 ms of `require` on its own and 1.68 ms with the kept list (2151.1 and
  3061.0 against 1383.8, fifteen runs): a module of one function that calls `pool:find` on an
  annotated pool takes 0.85 ms to load, one that calls `pool:intern` and `pool:find` 1.63 ms, and
  the same with the pool unannotated 0.23 ms (seven runs each, outside the lock). That is more
  than an order of 96 plugins gets back. Not taken.
- **A script list told by its last letter.** `open` leaves `.omwscripts` files out of a
  Context's content by lowering each name and matching a pattern. Looking at the last byte first
  made the content list of 512 names 1.41x (123.3 µs against 173.5, three runs), 0.1 µs a name,
  and cost 0.09 ms of `require` (1771.8 against 1681.3, fifteen runs), which is what it saves
  over 900 names. A tool opens one load order. Not taken.
- **The kept list's copy presized.** 27.87 µs against 28.80 for the changing list, five runs:
  no change, and `table.clone` replaced it.

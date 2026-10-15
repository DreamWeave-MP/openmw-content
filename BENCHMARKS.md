# Load order benchmarks

`bench/bench.jsl` times the package the way a tool reaches it: `@load-order` over an `@openmw`
Context for an install the bench writes. The install is four data folders, three masters of
1,001 records and 93 plugins of 101 (statics, lights, people, and cells of six references each),
1.4 MB and 12,396 records in 96 files, and a content list of 103 names, seven of them script
lists. Every plugin
names the three masters in one of three cases, every fourth the plugin before it, and every tenth
a master the order doesn't have. It opens the order whole, cut to two record types, and with
cells cut to their headers; opens a list of entries a third of which don't open; opens a content
list of 512 names no folder has a file of, through a Context that is nothing but that list, which
leaves the package's own work and none of `@tes3`'s or the disk's; finds every plugin's masters
in one list of the order's names, one plugin's in a list that is another from its first name at
every call, and one plugin's in a list that is another only at its last name; and asks for the
output folder and for an activation the content already has. Each workload is warmed
up, sized to a batch of about a tenth of a second, and reported as the median of seven batches,
with a full collection between them. Every result is compared with what the writer of the install
says it must be; the two changing-list rows with places found by a plain scan of the list, which
asks the package nothing.

`bench/cold.jsl` times what one process pays once: the `require` of this package's module with
`@dream/fs` and `@tes3` loaded first, then the first `open` of three plugins and the first
`masters`. Each line is a single sample, so it is run many times and the medians are compared.

```sh
jess run --package jpk/load-order --package jpk/openmw --package-path jpk \
  --capability filesystem.read --capability filesystem.write \
  jpk/load-order/bench/bench.jsl <scratch folder> [filter]

jess run --package jpk/load-order --package-path jpk \
  --capability filesystem.read --capability filesystem.write \
  jpk/load-order/bench/cold.jsl <scratch folder>
```

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other work while this ran
  (load average 0.4 to 1.1 over the runs).
- Date: 2026-10-13.
- Binary: the verified release build of Jess 0.1.0 on l3i 2.0.2 (Luau 0.742), the same one for
  both sides, and the same sibling packages.
- Base: `f1ad870`, the package before the move, run with the benches as they are now. Head:
  `d3a36cc`.
- Protocol: the whole of `bench.jsl` against an export of base, then head, five times over,
  back to back under one lock; each cell is the median of its five runs. `cold.jsl` the same
  way, thirty-one times over. A difference under 5 percent is called no change.
- These are the numbers of the review's run, which measured everything again. The run before it,
  of base against `5f63aa7`, had the one list at 3.28x (1235.2 against 376.9), the list that is
  another at every call at 0.93x (25.67 against 27.59), and `require @load-order` at 0.89x
  (1411.5 against 1585.9); it had no row for a list that is another only at its last name.

| Workload | Base, µs | Head, µs | Base / head |
|---|---:|---:|---:|
| open: 96 plugins of 103 content files, whole | 1819.8 | 1877.0 | no change |
| open: 96 plugins, the lights and statics of each | 2340.7 | 2323.1 | no change |
| open: 96 plugins, cells without their references | 3063.5 | 3115.5 | no change |
| open: 96 entries given, 32 of them missing, unreadable or not a plugin | 1380.5 | 1377.7 | no change |
| open: a content list of 512 names no folder has, 64 of them script lists | 175.1 | 175.2 | no change |
| masters: each of 96 plugins' in one list of the order's 96 names | 1236.4 | 381.3 | 3.24x |
| masters: one plugin's in a list of 96 names, another list at every call | 25.92 | 28.02 | 0.93x |
| masters: one plugin's in a list of 94 names, its last name another at every call | 26.24 | 30.12 | 0.87x |
| outputDirectory: the folder a generated plugin goes to | 1.476 | 1.530 | no change |
| activate: a name the content already has, in another case | 14.57 | 14.69 | no change |

| One cold process | Base, µs | Head, µs | Base / head |
|---|---:|---:|---:|
| require @dream/fs and @tes3 | 102610.2 | 103393.7 | no change |
| require @load-order, those loaded | 1419.6 | 1621.3 | 0.88x |
| first open, 3 plugins of a content list of 4 | 77.0 | 76.6 | no change |
| first masters, in 3 names | 13.55 | 14.19 | no change (0.95x) |
| require @load-order to the masters | 1519.8 | 1713.1 | 0.89x |

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
order answers as it always did; `tests/run.jsl` holds that, and the places of a list with a gap.
Only a plain table is walked against the copy. A list whose metatable says how it's walked, and
a function in a list's place, are walked once and never kept: `12c973c` walked such a function
twice, so it lost the names the first walk took or was refused by `table.clone`, and `d3a36cc`
put that right.

The same change is the three rows that lost. A caller that hands `masters` another list at every
call pays for the copy, and for the walk as far as the lists agree, and never uses them. Where the
lists part at the first name that is 1.0 µs a call for 96 names (the row is two calls), 8 percent
more; where they part only at the last, which is as long as the walk gets, 1.9 µs a call for 94
names, 15 percent more. No package does either today. And the module takes 0.20 ms longer to `require`
(0.88x), which every process that loads it pays whether it asks for masters or not:
`s3lightfixes` and `tes3merge` never do. Against the 103 ms the modules below it take to load,
that is 0.2 percent of the process; against what it buys, an order of 96 plugins gets 0.86 ms
back from its masters, and a tool that asks about fewer than about twenty plugins of such an
order gets back less than the load cost. What a call saves grows with the list: 2.4, 4.6, 9.3,
18.3 and 36.3 µs for a list of 24, 48, 96, 192 and 384 names (single runs outside the lock). So a
tool that asks about every plugin of its order, as `merged-lands` does, gets the load cost back
at about 46 plugins by that arithmetic, loses the 0.20 ms on an order of three, and gets 3.5 ms
back from its masters on one of 192.

What did not move is where the time is, which is not in this package. Over 96 plugins of 100
records handed in as entries (single runs outside the lock again), opening them is 1.33 ms:
reading the files is 0.52 of it, `tes3.open` framing them 0.57, and the same loop written out by
hand with no package in it 1.26. The package's own work on a file (its loop, the entry it builds,
the reason it words for a file that didn't open) is about 0.7 µs, 5 percent. A filtered open
calls the package once for every record, with one table read in it; the rest of that walk is
`@tes3`'s.

### A change at a time

Each commit against the one before it, on the rows it could touch: the three masters rows five
times warm and `cold.jsl` thirty-one times, the five sources alternating under one lock each,
medians. The masters rows are another session's than the table above, so their ratios against
base differ from it within the noise (0.96x here for the list that is another at every call,
0.90x for the last name).

| Commit | What it does | Row | Before, µs | After, µs | Before / after |
|---|---|---|---:|---:|---:|
| `90d88a1` | an entry's and a master's fields by record pattern | masters, one list | 1253.8 | 1270.1 | no change |
| | | masters, another list at every call | 26.21 | 26.14 | no change |
| | | masters, the last name another | 26.37 | 26.13 | no change |
| | | require @load-order | 1419.6 | 1458.6 | no change (0.97x) |
| `12c973c` | the last list's places kept | masters, one list | 1270.1 | 390.2 | 3.25x |
| | | masters, another list at every call | 26.14 | 29.11 | 0.90x |
| | | masters, the last name another | 26.13 | 31.46 | 0.83x |
| | | require @load-order | 1458.6 | 1600.1 | 0.91x |
| `5f63aa7` | the kept list one `table.clone` | masters, one list | 390.2 | 376.2 | no change |
| | | masters, another list at every call | 29.11 | 26.95 | 1.08x |
| | | masters, the last name another | 31.46 | 29.42 | 1.07x |
| | | require @load-order | 1600.1 | 1618.9 | no change |
| `d3a36cc` | a function in a list's place walked once | masters, one list | 376.2 | 380.9 | no change |
| | | masters, another list at every call | 26.95 | 27.35 | no change |
| | | masters, the last name another | 29.42 | 29.47 | no change |
| | | require @load-order | 1618.9 | 1621.3 | no change |

`5f63aa7` gives back part of what `12c973c` cost a changing list, 1.08x and 1.07x here; the two
runs of five before this one had it at 1.05x and 1.06x, at the edge of what the protocol can
show. It is also four lines shorter.

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

## Which modules are native, and why

Jess compiles to machine code only what is marked (`--!native` on a module, `@native` on one
function), and every load pays for what is marked. A module carries `--!native` when a row below
spends its time there and the module is small (12 KB or less); a larger module carries `@native`
on the functions the row spends its time in, and nothing else.

Measured 2026-10-14 with `jess 0.1.0`, the verified release build of jess `07c38cb` on l3i
2.0.3, on the i7-10870H, the one-minute load 1.19 and 1.48 at the start of the two
sessions. In each session the bench ran alternately on this package and on a copy of it with
every module marked, three fresh runs of `bench/bench.jsl` each, every run's row the median of
its batches; a column is the median of the three, and a ratio is against the all-marked runs of
the same session. Which functions a row spends its time in comes from `jess run --profile` of
that row alone, unmarked. The load cost is a fresh `jess run --package <this package>
--package-path jpk` of a script that only requires `@load-order`, the two sides alternating, the
median of five each after one warm-up.

| Requiring `@load-order` | All marked | This state |
| --- | ---: | ---: |
| Unmarked | 0.101 s | 0.100 s |
| Final | 0.102 s | 0.102 s |

| Row | All marked (ms) | Unmarked / all marked | Final (ms) | Final / all marked |
| --- | ---: | ---: | ---: | ---: |
| open: 96 plugins of 103 content files, whole | 2.033 | 0.985× | 2.038 | 1.003× |
| open: 96 plugins, the lights and statics of each | 2.759 | **1.097×** | 2.615 | 0.948× |
| open: 96 plugins, cells without their references | 4.022 | **1.072×** | 3.955 | 0.984× |
| open: 96 entries given, 32 of them missing, unreadable or not a plugin | 1.517 | 1.022× | 1.574 | 1.037× |
| open: a content list of 512 names no folder has, 64 of them script lists | 0.1949 | **1.327×** | 0.1883 | 0.966× |
| masters: each of 96 plugins' in one list of the order's 96 names | 0.5335 | **1.422×** | 0.5176 | 0.970× |
| masters: one plugin's in a list of 96 names, another list at every call | 0.03343 | **1.284×** | 0.03237 | 0.968× |
| masters: one plugin's in a list of 94 names, its last name another at every call | 0.03618 | **1.417×** | 0.03481 | 0.962× |
| outputDirectory: the folder a generated plugin goes to | 0.00173 | 0.987× | 0.00168 | 0.970× |
| activate: a name the content already has, in another case | 0.01637 | 1.013× | 0.01583 | 0.967× |

What carries the directive: `init`, whole, the package's only module. Unmarked, requiring
`@load-order` cost what all marked does, within a millisecond (0.0996 s against 0.1005 s), and
the opens and the master checks ran 1.07x to 1.42x slower. At 11 KB it costs less to compile than
one open of the order saves, so it stays marked, and no row is more than 5% slower than all marked.

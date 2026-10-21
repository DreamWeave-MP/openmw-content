+++
title = "openmw-content"
description = "A load order's content files, opened in order through esm: which file each entry resolves to, its masters, and what failed, as a Jess package in Luau."
date = 2026-10-21

[taxonomies]
tags = ["Jess", "Luau", "OpenMW"]

[extra]
sections = ["overview", "releases", "credits"]
+++

A load order's content files, opened in order through esm: which file each entry resolves to, its masters, and what failed, as a Jess package in Luau.

<!-- more -->

A [Jess](https://github.com/DreamWeave-MP/jess) package, `org.dreamweave.openmw-content`. Add it to a `jess.toml` and
`jess workspace sync` pins it from this site:

```toml
[dependencies]
"org.dreamweave.openmw-content" = "0.1"
```

Every release below is the package's own archive, with its content digest beside the archive's
SHA-256; `jess.lock` pins the first and checks both.

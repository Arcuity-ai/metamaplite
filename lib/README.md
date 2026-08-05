# lib/

This directory holds two dependencies that **cannot be downloaded from any live
repository** and are therefore bootstrapped by a script rather than resolved by
Gradle from a remote.

    bash scripts/fetch-nlm-jars.sh      # run once, after cloning
    ./gradlew build

`build.gradle` resolves them from here via a `flatDir` repository, so no
`mvn install:install-file` step is needed.

| File | Coordinate | Classes |
| --- | --- | --- |
| `context-2012.jar` | `context:context:2012` | 7 (`context.implementation.ConText`, …) |
| `bioc-1.0.1.jar` | `bioc:bioc:1.0.1` | 51 (`bioc.*`, `bioc.tool.*`) |

## Why they aren't just Maven dependencies

Both were only ever published to `https://metamap.nlm.nih.gov/maven2/`. That
host now returns **NXDOMAIN from NLM's own nameserver** (`lhcns1.nlm.nih.gov`) —
it is gone, not blocked locally. Neither jar is on Maven Central, and the
Internet Archive never captured either one directly.

What does survive is NLM's own published uber-jar,
`metamaplite-3.6.2rc4-standalone.jar`, which shades both libraries in.
`scripts/fetch-nlm-jars.sh` pulls that from the Internet Archive snapshot
`20240414132946` and extracts the two class trees back out. The classes are
NLM's originals, not a rebuild, and the script refuses to write `lib/` unless it
finds exactly the expected class counts.

Upstream shipped both jars inside the `public_mm_lite` binary distribution and
expected you to `mvn install:install-file` them — see `install-maven-artifacts.sh`
and the "install Context, BioC, and NLS NLP libraries" section of `README.md`.
**If you have a genuine `public_mm_lite` distribution, prefer it**: copy its
`lib/context-2012.jar` and `lib/bioc-1.0.1.jar` here and skip the script.

## Why the jars are not committed

This is a public fork of `LHNCBC/metamaplite`, so we do not redistribute
NLM/JavaConText binaries from it. `lib/*.jar` is gitignored. If this repository
is ever detached from the fork network and made private, committing the two jars
directly is a two-line change (drop the `lib/*.jar` line from `.gitignore`).

## Why not jitpack for BioC?

`com.github.openbiocuration:BioC_Java:c119c35b58` (used by the pre-migration
`build.gradle`) resolves and compiles, but it is a *different build* — 41 classes
versus 51 — and three abbreviation tests fail against it:
`MarkAbbreviationsTest.testLongFormShortForm`, `MarkAbbreviationsTest.testComplex`
and `TestUserDefinedAcronyms.test0`. It also pulls `edu.ucdenver.ccp:biolemmatizer-*`,
which is not on Maven Central at all. Use the script instead.

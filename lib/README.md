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

**MetaMapLite is not abandoned** — 3.6.2rc8 is current, which is exactly what
`pom.xml` targets. What changed is where the artifacts live.

Both jars were only ever published to `https://metamap.nlm.nih.gov/maven2/`.
NLM decommissioned that hostname — it now returns **NXDOMAIN from NLM's own
nameserver** (`lhcns1.nlm.nih.gov`), as does `ii.nlm.nih.gov` — and moved the
downloads to `data.lhncbc.nlm.nih.gov`, **behind UMLS Terminology Services
authentication**. The open Maven repository was retired with no public
replacement: the `umls-restricted` `maven2` path redirects to the UTS login and
the `public` path returns 403. Neither jar is on Maven Central.

So this is a licensing gate, not a dead project, and there are two ways in.

### Preferred: the official distribution

Both jars ship in NLM's binary distribution, in its `lib/` directory:

    https://data.lhncbc.nlm.nih.gov/umls-restricted/ii/tools/MetaMap/download/metamaplite/public_mm_lite_3.6.2rc8_binaryonly.zip

That URL requires a free UMLS/UTS account
(<https://uts.nlm.nih.gov/uts/signup-login>). `scripts/fetch-nlm-jars.sh` will
use it automatically if you export `UMLS_API_KEY` (UTS → Profile → API Key), or
you can download the zip by hand and run the script with `METAMAPLITE_ZIP`
pointing at it. If you already have a `public_mm_lite` distribution unpacked,
simply copy its two jars here and skip the script entirely.

This route gives you the jars matching 3.6.2rc8.

### Fallback: NLM's archived uber-jar

Without a UTS account, the script extracts the class trees from NLM's own
`metamaplite-3.6.2rc4-standalone.jar`, which shades both libraries in,
retrieved from the Internet Archive snapshot `20240414132946`. The classes are
NLM's originals rather than a rebuild, and the script refuses to write `lib/`
unless it finds exactly the expected class counts — but note this is the older
**rc4** build, not rc8.

Upstream's own instructions assumed you had the distribution and would
`mvn install:install-file` the jars — see `install-maven-artifacts.sh` and the
"install Context, BioC, and NLS NLP libraries" section of `README.md`.

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

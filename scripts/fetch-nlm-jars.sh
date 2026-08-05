#!/usr/bin/env bash
#
# Bootstrap the two dependencies that cannot be downloaded from any live
# repository. Run once after cloning, before the first Gradle build:
#
#     bash scripts/fetch-nlm-jars.sh
#     ./gradlew build
#
# Why this exists
# ---------------
# bioc:bioc:1.0.1 and context:context:2012 were only ever published to
# https://metamap.nlm.nih.gov/maven2/. That host now returns NXDOMAIN from NLM's
# own nameserver (lhcns1.nlm.nih.gov) -- it is gone, not blocked. Neither jar is
# on Maven Central, and the Internet Archive never captured either one directly.
#
# What it does survive in is NLM's own published uber-jar, which shades both
# libraries in. This script pulls that jar from the Internet Archive and
# extracts the two class trees back out into lib/, where build.gradle's
# flatDir repository picks them up.
#
# The jars are NOT committed: this is a public fork of LHNCBC/metamaplite, and
# we do not redistribute NLM/JavaConText binaries from it.
#
# If you have a genuine public_mm_lite distribution, skip this script entirely
# and copy its lib/context-2012.jar and lib/bioc-1.0.1.jar into lib/ instead.

set -euo pipefail

cd "$(dirname "$0")/.."
LIB="lib"
SRC_JAR_URL="http://web.archive.org/web/20240414132946id_/https://metamap.nlm.nih.gov/maven2/gov/nih/nlm/nls/metamaplite/3.6.2rc4/metamaplite-3.6.2rc4-standalone.jar"

# Content hashes of the extracted class trees (not of the download itself --
# the archived uber-jar is ~390MB and we only keep two small slices of it).
EXPECT_CONTEXT_CLASSES=7
EXPECT_BIOC_CLASSES=51

mkdir -p "$LIB"

if [[ -f "$LIB/context-2012.jar" && -f "$LIB/bioc-1.0.1.jar" ]]; then
    echo "[skip] $LIB/context-2012.jar and $LIB/bioc-1.0.1.jar already present."
    echo "       Delete them first if you want to re-fetch."
    exit 0
fi

JAR_BIN="${JAVA_HOME:+$JAVA_HOME/bin/jar}"
JAR_BIN="${JAR_BIN:-jar}"
command -v "$JAR_BIN" >/dev/null 2>&1 || {
    echo "ERROR: 'jar' not found. Set JAVA_HOME to a JDK (17+) and retry." >&2
    exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[1/3] Downloading NLM's archived metamaplite-3.6.2rc4-standalone.jar (~390MB)..."
echo "      This is a one-time bootstrap; it is not needed for later builds."
curl -fSL --retry 3 --retry-delay 5 --max-time 1800 -o "$WORK/mml.jar" "$SRC_JAR_URL"

echo "[2/3] Extracting context/ and bioc/ ..."
( cd "$WORK" && "$JAR_BIN" xf mml.jar context/ bioc/ )

n_ctx=$(find "$WORK/context" -name '*.class' | wc -l)
n_bioc=$(find "$WORK/bioc" -name '*.class' | wc -l)
if [[ "$n_ctx" -ne "$EXPECT_CONTEXT_CLASSES" || "$n_bioc" -ne "$EXPECT_BIOC_CLASSES" ]]; then
    echo "ERROR: unexpected contents (context=$n_ctx want $EXPECT_CONTEXT_CLASSES," >&2
    echo "       bioc=$n_bioc want $EXPECT_BIOC_CLASSES). Refusing to write $LIB." >&2
    exit 1
fi

echo "[3/3] Packaging into $LIB ..."
( cd "$WORK" && "$JAR_BIN" cf context-2012.jar context/ && "$JAR_BIN" cf bioc-1.0.1.jar bioc/ )
mv "$WORK/context-2012.jar" "$WORK/bioc-1.0.1.jar" "$LIB/"

echo
echo "Done:"
ls -l "$LIB"/*.jar
echo
echo "Now run:  ./gradlew build"

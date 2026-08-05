#!/usr/bin/env bash
#
# Bootstrap the two dependencies that Gradle cannot resolve from any public
# repository. Run once after cloning, before the first build:
#
#     bash scripts/fetch-nlm-jars.sh
#     ./gradlew build
#
# Why this exists
# ---------------
# bioc:bioc:1.0.1 and context:context:2012 were only ever published to
# https://metamap.nlm.nih.gov/maven2/. MetaMapLite itself is alive and well --
# 3.6.2rc8 is current -- but NLM decommissioned that hostname (it is now
# NXDOMAIN, as is ii.nlm.nih.gov), moved the downloads to
# data.lhncbc.nlm.nih.gov, and put them behind UMLS Terminology Services
# authentication. The open Maven repository was retired with no public
# replacement: the umls-restricted maven2 path redirects to the UTS login and
# the public path returns 403. Neither jar is on Maven Central.
#
# Two ways to get them, in order of preference:
#
#   1. OFFICIAL (preferred). The jars ship in NLM's binary distribution, inside
#      its lib/ directory. Requires a free UMLS/UTS account:
#      https://uts.nlm.nih.gov/uts/signup-login
#      Either set UMLS_API_KEY (Profile -> API Key in UTS) and let this script
#      fetch it, or download the zip by hand and point METAMAPLITE_ZIP at it.
#
#   2. FALLBACK. Extract the class trees from NLM's own uber-jar for the older
#      3.6.2rc4 release, retrieved from the Internet Archive. Same NLM classes,
#      no account needed, but an older build than pom.xml targets.
#
# If you already have a public_mm_lite distribution unpacked somewhere, just
# copy its lib/context-2012.jar and lib/bioc-1.0.1.jar into lib/ and skip this.

set -euo pipefail

cd "$(dirname "$0")/.."
LIB="lib"

MML_VERSION="3.6.2rc8"
OFFICIAL_ZIP_URL="https://data.lhncbc.nlm.nih.gov/umls-restricted/ii/tools/MetaMap/download/metamaplite/public_mm_lite_${MML_VERSION}_binaryonly.zip"
UTS_DOWNLOAD_API="https://uts-ws.nlm.nih.gov/download"
ARCHIVE_JAR_URL="http://web.archive.org/web/20240414132946id_/https://metamap.nlm.nih.gov/maven2/gov/nih/nlm/nls/metamaplite/3.6.2rc4/metamaplite-3.6.2rc4-standalone.jar"

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

extract_from_zip() {   # $1 = path to public_mm_lite zip
    echo "  Extracting lib/ from $(basename "$1") ..."
    unzip -j -o -q "$1" '*/lib/context-2012.jar' '*/lib/bioc-1.0.1.jar' \
                        'lib/context-2012.jar'   'lib/bioc-1.0.1.jar' -d "$WORK" || true
    if [[ -f "$WORK/context-2012.jar" && -f "$WORK/bioc-1.0.1.jar" ]]; then
        mv "$WORK/context-2012.jar" "$WORK/bioc-1.0.1.jar" "$LIB/"
        return 0
    fi
    echo "  Could not find both jars inside the zip." >&2
    return 1
}

# ---- route 1: a zip the user already downloaded --------------------------
if [[ -n "${METAMAPLITE_ZIP:-}" ]]; then
    echo "[official] Using METAMAPLITE_ZIP=$METAMAPLITE_ZIP"
    extract_from_zip "$METAMAPLITE_ZIP"
    echo; ls -l "$LIB"/*.jar; echo; echo "Now run:  ./gradlew build"; exit 0
fi

# ---- route 2: UTS API key ------------------------------------------------
if [[ -n "${UMLS_API_KEY:-}" ]]; then
    echo "[official] Downloading public_mm_lite_${MML_VERSION}_binaryonly.zip via UTS ..."
    if curl -fSL --retry 3 --max-time 1800 -o "$WORK/mml.zip" \
            --get --data-urlencode "url=${OFFICIAL_ZIP_URL}" \
                 --data-urlencode "apiKey=${UMLS_API_KEY}" \
            "$UTS_DOWNLOAD_API" && [[ -s "$WORK/mml.zip" ]] \
       && file "$WORK/mml.zip" | grep -qi zip; then
        extract_from_zip "$WORK/mml.zip"
        echo; ls -l "$LIB"/*.jar; echo; echo "Now run:  ./gradlew build"; exit 0
    fi
    echo "  UTS download failed; falling back to the Internet Archive." >&2
fi

# ---- route 3: Internet Archive fallback ----------------------------------
echo "[fallback] No UMLS_API_KEY / METAMAPLITE_ZIP set."
echo "           Extracting NLM's classes from the archived 3.6.2rc4 uber-jar."
echo "           For the jars matching pom.xml's ${MML_VERSION}, get a free UTS"
echo "           account at https://uts.nlm.nih.gov/uts/signup-login and re-run"
echo "           with UMLS_API_KEY set."
echo
echo "  Downloading (~390MB, one time) ..."
curl -fSL --retry 3 --retry-delay 5 --max-time 1800 -o "$WORK/mml.jar" "$ARCHIVE_JAR_URL"

echo "  Extracting context/ and bioc/ ..."
( cd "$WORK" && "$JAR_BIN" xf mml.jar context/ bioc/ )

n_ctx=$(find "$WORK/context" -name '*.class' | wc -l)
n_bioc=$(find "$WORK/bioc" -name '*.class' | wc -l)
if [[ "$n_ctx" -ne "$EXPECT_CONTEXT_CLASSES" || "$n_bioc" -ne "$EXPECT_BIOC_CLASSES" ]]; then
    echo "ERROR: unexpected contents (context=$n_ctx want $EXPECT_CONTEXT_CLASSES," >&2
    echo "       bioc=$n_bioc want $EXPECT_BIOC_CLASSES). Refusing to write $LIB." >&2
    exit 1
fi

( cd "$WORK" && "$JAR_BIN" cf context-2012.jar context/ && "$JAR_BIN" cf bioc-1.0.1.jar bioc/ )
mv "$WORK/context-2012.jar" "$WORK/bioc-1.0.1.jar" "$LIB/"

echo
ls -l "$LIB"/*.jar
echo
echo "Now run:  ./gradlew build"

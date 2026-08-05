#!/usr/bin/env bash
#
# Bootstrap the two dependencies that Gradle cannot resolve from any public
# repository. Run once after cloning, before the first build:
#
#     export UMLS_API_KEY=...          # UTS -> Profile -> API Key
#     bash scripts/fetch-nlm-jars.sh
#     ./gradlew build
#
# Why this exists
# ---------------
# bioc:bioc:1.0.1 and context:context:2012 were only ever published to
# https://metamap.nlm.nih.gov/maven2/. MetaMapLite itself is alive and well --
# 3.6.2rc8 is current -- but NLM decommissioned that hostname (now NXDOMAIN, as
# is ii.nlm.nih.gov), moved the downloads to data.lhncbc.nlm.nih.gov, and put
# them behind UMLS Terminology Services authentication. The open Maven
# repository was retired with no public replacement. Neither jar is on Maven
# Central. This is a licensing gate, not a dead project.
#
# Both jars ship in NLM's binary distribution, under its lib/ directory. This
# script authenticates to UTS and pulls them straight out of it.
#
# Routes, in order of preference:
#   1. UMLS_API_KEY   -- authenticate to UTS and download (preferred; gives the
#                        jars matching pom.xml's 3.6.2rc8)
#   2. METAMAPLITE_ZIP -- path to a public_mm_lite zip you already downloaded
#   3. neither        -- fall back to extracting NLM's classes from the
#                        archived 3.6.2rc4 uber-jar on the Internet Archive
#                        (older build, no account required)
#
# If you already have a public_mm_lite distribution unpacked, just copy its
# lib/context-2012.jar and lib/bioc-1.0.1.jar into lib/ and skip this.

set -euo pipefail

cd "$(dirname "$0")/.."
LIB="lib"

MML_VERSION="3.6.2rc8"
OFFICIAL_ZIP_URL="https://data.lhncbc.nlm.nih.gov/umls-restricted/ii/tools/MetaMap/download/metamaplite/public_mm_lite_${MML_VERSION}_binaryonly.zip"
CAS_API_KEY_URL="https://utslogin.nlm.nih.gov/cas/v1/api-key"
ARCHIVE_JAR_URL="http://web.archive.org/web/20240414132946id_/https://metamap.nlm.nih.gov/maven2/gov/nih/nlm/nls/metamaplite/3.6.2rc4/metamaplite-3.6.2rc4-standalone.jar"

EXPECT_CONTEXT_CLASSES=7
EXPECT_BIOC_CLASSES=51

mkdir -p "$LIB"

if [[ -f "$LIB/context-2012.jar" && -f "$LIB/bioc-1.0.1.jar" && -z "${FORCE_FETCH:-}" ]]; then
    echo "[skip] $LIB/context-2012.jar and $LIB/bioc-1.0.1.jar already present."
    echo "       Re-run with FORCE_FETCH=1 to replace them."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

extract_from_zip() {   # $1 = path to a public_mm_lite zip
    unzip -j -o -q "$1" '*/lib/context-2012.jar' '*/lib/bioc-1.0.1.jar' \
                        'lib/context-2012.jar'   'lib/bioc-1.0.1.jar' \
                        -d "$WORK/extracted" 2>/dev/null || true
    if [[ -f "$WORK/extracted/context-2012.jar" && -f "$WORK/extracted/bioc-1.0.1.jar" ]]; then
        mv "$WORK/extracted/context-2012.jar" "$WORK/extracted/bioc-1.0.1.jar" "$LIB/"
        return 0
    fi
    echo "  ERROR: could not find both jars inside $(basename "$1")." >&2
    return 1
}

done_msg() { echo; ls -l "$LIB"/*.jar; echo; echo "Now run:  ./gradlew build"; }

# ---- route 2: a zip already on disk --------------------------------------
if [[ -n "${METAMAPLITE_ZIP:-}" ]]; then
    echo "[official] Using METAMAPLITE_ZIP=$METAMAPLITE_ZIP"
    extract_from_zip "$METAMAPLITE_ZIP"
    done_msg; exit 0
fi

# ---- route 1: UTS ---------------------------------------------------------
# data.lhncbc.nlm.nih.gov/umls-restricted/ is CAS-protected. The uts-ws.nlm.nih.gov
# /download proxy does NOT serve these paths (it only handles download.nlm.nih.gov
# release files) -- it silently returns the UTS login page with HTTP 200. The
# working flow is: api-key -> ticket-granting ticket -> service ticket, then GET
# the URL with ?ticket=. A cookie jar is required: CAS validates the ticket, sets
# a session cookie and redirects, and without -c/-b the redirect lands back on
# the login page.
if [[ -n "${UMLS_API_KEY:-}" ]]; then
    echo "[official] Authenticating to UTS ..."
    tgt=$(curl -sS --max-time 90 -d "apikey=${UMLS_API_KEY}" "$CAS_API_KEY_URL" \
          | tr -d '\r' | grep -oE "${CAS_API_KEY_URL}/TGT-[A-Za-z0-9._-]+" | head -1) || true
    if [[ -z "$tgt" ]]; then
        echo "  ERROR: no ticket-granting ticket -- is UMLS_API_KEY valid?" >&2
        exit 1
    fi

    st=$(curl -sS --max-time 90 -d "service=${OFFICIAL_ZIP_URL}" "$tgt" | tr -d '\r\n') || true
    if [[ ! "$st" =~ ^ST- ]]; then
        echo "  ERROR: did not get a service ticket (got: ${st:0:40})" >&2
        exit 1
    fi

    echo "[official] Downloading public_mm_lite_${MML_VERSION}_binaryonly.zip (~74MB) ..."
    curl -fsSL --retry 3 --retry-delay 5 --max-time 1800 \
         -c "$WORK/cas-cookies" -b "$WORK/cas-cookies" \
         -o "$WORK/mml.zip" "${OFFICIAL_ZIP_URL}?ticket=${st}"

    if ! file "$WORK/mml.zip" | grep -qi 'zip archive'; then
        echo "  ERROR: UTS returned $(file -b "$WORK/mml.zip"), not a zip." >&2
        echo "         The ticket was rejected; check the account's UMLS licence." >&2
        exit 1
    fi

    extract_from_zip "$WORK/mml.zip"
    echo "[official] Got the jars matching ${MML_VERSION}."
    done_msg; exit 0
fi

# ---- route 3: Internet Archive fallback ----------------------------------
echo "[fallback] UMLS_API_KEY and METAMAPLITE_ZIP are both unset."
echo "           Extracting NLM's classes from the archived 3.6.2rc4 uber-jar."
echo "           For the jars matching ${MML_VERSION}, get a free UTS account at"
echo "           https://uts.nlm.nih.gov/uts/signup-login and set UMLS_API_KEY."
echo

JAR_BIN="${JAVA_HOME:+$JAVA_HOME/bin/jar}"
JAR_BIN="${JAR_BIN:-jar}"
command -v "$JAR_BIN" >/dev/null 2>&1 || {
    echo "ERROR: 'jar' not found. Set JAVA_HOME to a JDK (17+) and retry." >&2
    exit 1
}

echo "  Downloading (~390MB, one time) ..."
curl -fsSL --retry 3 --retry-delay 5 --max-time 1800 -o "$WORK/mml.jar" "$ARCHIVE_JAR_URL"

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
done_msg

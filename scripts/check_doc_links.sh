#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# check_doc_links.sh — every relative link in our markdown must resolve.
#
# Extracted from an inline docs.yml step that had two bugs:
#
#   1. It tested `[ -e "docs/DISTRIBUTION.md#release-signing" ]` — anchor and
#      all — so a PERFECTLY VALID anchor link was reported broken and docs.yml
#      went red on master. The link was right; the checker was wrong. A gate
#      that cries wolf gets ignored, which is how the OTHER real breakage below
#      survived.
#   2. It only scanned `README.md` + `docs/**`, so SECURITY.md, CONTRIBUTING.md,
#      ROADMAP.md and friends were never checked. Both had dead links; the
#      security policy's were pointing at things that never existed.
#
# So this checks every tracked .md, strips the anchor before the file test, and
# — when the target is markdown — verifies the anchor actually names a heading,
# because a link to a renamed heading is broken in the way that matters to a
# reader even though the file still exists.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# GitHub's heading->anchor slug: lowercase, strip anything but word/space/hyphen,
# spaces to hyphens. Close enough for our headings; it is only ever used to
# CONFIRM an anchor exists, and anchor checks are skipped for non-markdown.
slugify() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9 _-]//g; s/ +/-/g'
}

fail=0
while IFS= read -r f; do
    dir="$(dirname "$f")"
    # Capture the link target of every []() whose target is not http(s) or a
    # bare in-page #anchor.
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        case "$target" in
            http://*|https://*|mailto:*|'#'*) continue ;;
        esac
        path="${target%%#*}"        # strip the anchor for the file test
        anchor="${target#*#}"
        [ "$anchor" = "$target" ] && anchor=""

        # Resolve relative to the file, then to the repo root.
        resolved=""
        if [ -e "$dir/$path" ]; then resolved="$dir/$path"
        elif [ -e "$path" ]; then resolved="$path"
        else
            echo "BROKEN FILE  $f -> $target"
            fail=1
            continue
        fi

        # Anchor check, markdown targets only.
        if [ -n "$anchor" ] && case "$resolved" in *.md) true ;; *) false ;; esac; then
            found=0
            while IFS= read -r heading; do
                [ "$(slugify "$heading")" = "$anchor" ] && { found=1; break; }
            done < <(grep -E '^#{1,6} ' "$resolved" | sed -E 's/^#{1,6} +//')
            if [ "$found" -eq 0 ]; then
                echo "BROKEN ANCHOR  $f -> $target  (no heading in $resolved slugs to '$anchor')"
                fail=1
            fi
        fi
    done < <(grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//' | sed -E 's/ +".*"$//')
done < <(git ls-files '*.md')

if [ "$fail" -ne 0 ]; then
    echo
    echo "FAIL: the links above do not resolve."
    exit 1
fi
echo "OK: every relative markdown link resolves (file + anchor)."

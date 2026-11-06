#!/bin/bash
#
# The install test hands each architecture's ISO from the build job to its
# install jobs as an artifact. "Re-run failed jobs" starts a new attempt
# without the build jobs that passed, and their install jobs then fetch the
# ISO an earlier attempt uploaded (download-artifact reads the run's earlier
# attempts too). So the ISO's name must not carry the attempt, and a build
# that does run again replaces its ISO, since a name is unique in a run.
# The test results stay per attempt: the comment workflow reads
# install-test-<run>-<attempt>*.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORKFLOW="$ROOT/.github/workflows/install-test.yml"

fail() { echo "FAIL: $*" >&2; exit 1; }

# Every step that names this artifact, each from its "- " line to the next
# line indented no deeper, separated by a line holding "--".
steps_of() {
  awk -v name="$1" '
    function flush() { if (keep) printf "%s--\n", block; keep = 0 }
    match($0, /^ *- /) { flush(); indent = RLENGTH - 2; block = ""; open = 1 }
    open && $0 !~ /^ *$/ && !match($0, /^ *- /) { match($0, /^ */); if (RLENGTH <= indent) { flush(); open = 0 } }
    open { block = block $0 "\n" }
    open && index($0, "name: " name) { keep = 1 }
    END { flush() }
  ' "$WORKFLOW"
}

isos=$(sed -nE 's/^ *name: (iso-.*)$/\1/p' "$WORKFLOW")
# The build's own name ends in its architecture's expression, the install
# jobs' in the architecture itself.
upload=$(grep -vE -- '-x86_64$' <<<"$isos" | sort -u) || fail "the build uploads no per-architecture ISO artifact"
[[ $(grep -c "" <<<"$upload") == 1 ]] || fail "more than one ISO upload name: $upload"
grep -F 'run_attempt' <<<"$isos" && fail "an ISO artifact name carries the attempt, which a partial re-run's install jobs never find"
for arch in x86_64; do
  want=${upload%-*}-$arch
  grep -Fxq "$want" <<<"$isos" || fail "no install job fetches $want, the ISO the $arch build uploads"
done
uploads=$(steps_of "$upload")
[[ $(grep -c '^--$' <<<"$uploads") == 1 ]] || fail "expected one step to upload $upload"
[[ $(grep -cE '^ *overwrite: true$' <<<"$uploads") == $(grep -c '^--$' <<<"$uploads") ]] \
  || fail "an ISO upload step cannot replace its ISO when a build runs again"

# GitHub's runners always use GitHub's artifact storage, regardless of author.
grep -Eq '^ *uses: actions/upload-artifact@' <<<"$uploads" || fail "the ISO upload does not use GitHub's artifact action"
grep -Eq '^ *if:' <<<"$uploads" && fail "the ISO upload is conditional"
for setting in 'release/*.iso' 'test-runs/build-seconds' 'compression-level: 0' 'retention-days: 7'; do
  grep -Fxq "          $setting" <<<"$uploads" || grep -Fxq "            $setting" <<<"$uploads" \
    || fail "the ISO upload lacks $setting"
done

# Every test-result artifact keeps the run and the attempt, as the comment
# workflow reads them.
results=$(sed -nE 's/^ *name: (install-test-.*)$/\1/p' "$WORKFLOW")
[[ $(grep -c "" <<<"$results") == 1 ]] || fail "expected the x86_64 result artifact, found: $results"
while read -r name; do
  [[ $name == *'${{ github.run_id }}-${{ github.run_attempt }}-'* ]] || fail "result artifact $name does not carry its run and attempt"
done <<<"$results"
grep -Fq -- '-p "install-test-$RUN_ID-$ATTEMPT*"' "$ROOT/.github/workflows/install-test-comment.yml" \
  || fail "the comment workflow no longer reads install-test-<run>-<attempt>*"

# Each install job waits for its own architecture's build and no other. A
# job that needs a matrix job waits for all of its legs and is skipped when
# any of them fails, so one architecture's failed build would skip the other
# architecture's installs, though its ISO built.
job_of() {
  awk -v job="$1" '/^  [A-Za-z0-9_-]+:/ { keep = ($0 == "  " job ":") } keep' "$WORKFLOW"
}
for arch in x86_64; do
  job_of "build-$arch" | grep -Eq "^      ARCH: $arch\$" || fail "no build-$arch job builds the $arch ISO"
  fetchers=0
  for job in $(sed -nE 's/^  ([A-Za-z0-9_-]+):$/\1/p' "$WORKFLOW"); do
    block=$(job_of "$job")
    grep -Fxq "          name: iso-\${{ github.run_id }}-$arch" <<<"$block" || continue
    fetchers=$((fetchers + 1))
    needs=$(sed -nE 's/^    needs: *//p' <<<"$block")
    builds=$(grep -oE 'build[A-Za-z0-9_-]*' <<<"$needs" | paste -sd ' ' - || true)
    [[ $builds == "build-$arch" ]] || fail "$job fetches the $arch ISO but waits for ${builds:-no build}, not only build-$arch (needs: $needs)"
  done
  ((fetchers > 0)) || fail "no install job fetches the $arch ISO"
  downloads=$(steps_of "iso-\${{ github.run_id }}-$arch")
  [[ $(grep -c '^--$' <<<"$downloads") == "$fetchers" ]] || fail "expected one ISO download per install job"
  [[ $(grep -cE '^ *uses: actions/download-artifact@' <<<"$downloads") == "$fetchers" ]] || fail "an ISO download does not use GitHub's artifact action"
  grep -Eq '^ *if:' <<<"$downloads" && fail "an ISO download is conditional"
done
echo "install test artifact names passed"

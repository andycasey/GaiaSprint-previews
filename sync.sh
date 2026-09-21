#!/usr/bin/env bash
# Build a static preview of every open PR into SOURCE_REPO's BASE_BRANCH and
# publish each one under pr-<number>/ in this repo (served by GitHub Pages).
set -euo pipefail

SOURCE_REPO="${SOURCE_REPO:-davidwhogg/GaiaSprint}"
BASE_BRANCH="${BASE_BRANCH:-gh-pages}"
# Path prefix under which this repo is served. Set to "" if a custom domain
# (e.g. previews.gaia.lol) is pointed at this repo, and update SITE_URL.
SITE_PREFIX="${SITE_PREFIX:-/GaiaSprint-previews}"
SITE_URL="${SITE_URL:-https://andycasey.github.io/GaiaSprint-previews}"
MARKER="<!-- gaiasprint-preview -->"

root="$PWD"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

gh api --paginate "repos/$SOURCE_REPO/pulls?base=$BASE_BRANCH&state=open&per_page=100" \
  --jq '[.[] | {number, title, html_url, user: .user.login, sha: .head.sha, label: .head.label}]' \
  | jq -s 'add // []' > "$work/prs.json"
echo "Open PRs into $BASE_BRANCH: $(jq length "$work/prs.json")"

git clone -q "https://github.com/$SOURCE_REPO.git" "$work/src"

declare -a keep=() built=()
while IFS=$'\t' read -r num sha; do
  dir="pr-$num"
  keep+=("$dir")
  if [[ -f "$dir/PREVIEW_SHA" && "$(cat "$dir/PREVIEW_SHA")" == "$sha" ]]; then
    echo "$dir: up to date ($sha)"
    continue
  fi
  echo "$dir: building $sha"
  git -C "$work/src" fetch -q origin "pull/$num/head"
  src="$work/build-$num"
  git -C "$work/src" worktree add -q --detach "$src" "$sha"
  # Make the site think it lives at SITE_PREFIX/pr-N so relative_url links resolve.
  printf '\nurl: ""\nbaseurl: "%s/%s"\n' "$SITE_PREFIX" "$dir" >> "$src/_config.yml"
  rm -rf "$dir"
  # --safe: no custom plugins, no symlinks. The PR's content is untrusted.
  JEKYLL_ENV=production PAGES_REPO_NWO="$SOURCE_REPO" \
    bundle exec jekyll build --safe --source "$src" --destination "$root/$dir"
  echo "$sha" > "$dir/PREVIEW_SHA"
  built+=("$num")
done < <(jq -r '.[] | "\(.number)\t\(.sha)"' "$work/prs.json")

# Drop previews for PRs that are no longer open.
for d in pr-*/; do
  d="${d%/}"
  [[ -d "$d" ]] || continue
  if [[ ! " ${keep[*]-} " =~ " $d " ]]; then
    echo "$d: PR closed, removing"
    rm -rf "$d"
  fi
done

# Index page.
{
  cat <<HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>GaiaSprint PR previews</title>
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:48em;margin:3em auto;padding:0 1em}code{font-size:.9em}</style>
</head><body>
<h1>GaiaSprint PR previews</h1>
<p>Live builds of open pull requests into <a href="https://github.com/$SOURCE_REPO/tree/$BASE_BRANCH">$SOURCE_REPO:$BASE_BRANCH</a>
(the source of <a href="https://gaia.lol">gaia.lol</a>). Refreshed every 10 minutes.</p>
<ul>
HTML
  jq -r --arg u "$SITE_URL" '.[] | "<li><a href=\"\($u)/pr-\(.number)/\">PR #\(.number): \(.title)</a> &mdash; <a href=\"\(.html_url)\">\(.label)</a> @ <code>\(.sha[0:7])</code></li>"' "$work/prs.json"
  [[ "$(jq length "$work/prs.json")" == 0 ]] && echo "<li><i>No open pull requests.</i></li>"
  echo "</ul><p><small>Last checked $(date -u +'%Y-%m-%d %H:%M UTC').</small></p></body></html>"
} > index.html

git add -A
if git diff --cached --quiet -- . ':!index.html'; then
  echo "No preview changes."
  git checkout -- index.html 2>/dev/null || true
  git reset -q
  exit 0
fi
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "Sync previews: $(jq -r 'map("#\(.number)") | join(", ")' "$work/prs.json")"
git push -q

# Sticky comment on each PR we (re)built, if a token was provided.
if [[ -n "${PR_COMMENT_TOKEN:-}" ]]; then
  export GH_TOKEN="$PR_COMMENT_TOKEN"
  for num in "${built[@]-}"; do
    [[ -n "$num" ]] || continue
    sha="$(cat "pr-$num/PREVIEW_SHA")"
    body="$MARKER
:eyes: Preview of this PR: $SITE_URL/pr-$num/ (built from ${sha:0:7}; updates within ~10 min of each push)."
    id="$(gh api --paginate "repos/$SOURCE_REPO/issues/$num/comments" \
          --jq ".[] | select(.body | startswith(\"$MARKER\")) | .id" | head -n1)"
    if [[ -n "$id" ]]; then
      gh api -X PATCH "repos/$SOURCE_REPO/issues/comments/$id" -f body="$body" >/dev/null
    else
      gh api -X POST "repos/$SOURCE_REPO/issues/$num/comments" -f body="$body" >/dev/null
    fi
    echo "pr-$num: comment updated"
  done
fi

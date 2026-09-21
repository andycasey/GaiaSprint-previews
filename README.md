# GaiaSprint PR previews

Static previews of open pull requests into
[davidwhogg/GaiaSprint:gh-pages](https://github.com/davidwhogg/GaiaSprint/tree/gh-pages),
the source of <https://gaia.lol>.

- Index: <https://andycasey.github.io/GaiaSprint-previews/>
- Each PR: `https://andycasey.github.io/GaiaSprint-previews/pr-<number>/`

[`sync.sh`](sync.sh) runs every 10 minutes (and on demand from the Actions tab).
It lists open PRs, builds each head with Jekyll in safe mode using the same
`github-pages` gem GitHub uses, writes the output to `pr-<number>/`, and removes
previews for PRs that have closed. Only `pr-*/` directories and `index.html`
are generated; everything else is hand-maintained.

Optional: add a repository secret `PR_COMMENT_TOKEN` (a token with write access
to issues on davidwhogg/GaiaSprint) and the sync will post a sticky comment on
each PR with its preview link.

To serve from a custom domain such as `previews.gaia.lol`, add a `CNAME` file
here, point a DNS CNAME at `andycasey.github.io`, and set `SITE_PREFIX=""` and
`SITE_URL` in the workflow.

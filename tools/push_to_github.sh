#!/usr/bin/env bash
# Publish this project to a GitHub repository.
#
#   GH_TOKEN=ghp_xxxxxxxx tools/push_to_github.sh https://github.com/<user>/<repo>.git [branch]
#
# or, if you already have SSH keys / a credential helper set up:
#
#   tools/push_to_github.sh git@github.com:<user>/<repo>.git
#
# The token is used only for this one push (via an in-memory credential helper), never
# written to .git/config, so a public copy of the repo cannot leak it.
set -euo pipefail

REPO="${1:-${GH_REPO:-}}"
BRANCH="${2:-main}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$REPO" ]; then
	echo "usage: GH_TOKEN=<token> $0 <repo-url> [branch]" >&2
	exit 2
fi

cd "$ROOT"

if [ ! -d .git ]; then
	echo "== no git repository here, initialising =="
	git init -b main -q
	git add -A
	git -c user.name="${GIT_AUTHOR_NAME:-Last Move Dev}" \
	    -c user.email="${GIT_AUTHOR_EMAIL:-dev@example.com}" \
	    commit -q -m "THE LAST MOVE: project snapshot"
fi

git remote remove origin >/dev/null 2>&1 || true
git remote add origin "$REPO"

CURRENT="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CURRENT" != "$BRANCH" ]; then
	git branch -m "$BRANCH"
fi

echo "== pushing $(git rev-list --count HEAD) commit(s), $(git ls-files | wc -l) files to $REPO ($BRANCH) =="

if [[ "$REPO" == https://* && -n "${GH_TOKEN:-}" ]]; then
	# ephemeral credential helper: echoes the token to git for this command only
	HELPER='!f() { echo "username=x-access-token"; echo "password=${GH_TOKEN}"; }; f'
	git -c credential.helper= -c "credential.helper=$HELPER" push -u origin "$BRANCH"
else
	git push -u origin "$BRANCH"
fi

echo "== done. Verify: $(echo "$REPO" | sed 's/\.git$//') =="

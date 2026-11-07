#!/bin/sh
# Builds the tree the release gate judges: a fresh clone holding a commit's exact bytes, so no ignored,
# hidden or stray file of the checkout can steer a leg. Usage: release-clone.sh <commit> <dir>
#
# The files come from release-export.sh, because a checkout would apply this machine's filters and eol
# settings. A few things the guards judge are this checkout's state and no commit holds them. Each is
# copied as it stands, so a rule reads here what it reads there, and one that is missing stays missing:
# - origin's URL, which repo.luxpm_receipt_current compares with the receipt;
# - core.hooksPath, which secret.githooks_wired reads, and which decides whether the push runs pre-push;
# - the reflog, by which repo.guard_status_current tells whether code landed after the status files;
# - the hook heartbeat, by which repo.hooks_wired knows the hooks ever ran;
# - Makefile.local, which names the registry, and which the preflight has limited to plain settings.
commit=$1
dir=$2

die() {
	printf 'release: %s\n' "$1" >&2
	exit 1
}

git clone -q --no-checkout . "$dir" || die "cannot clone this repository into $dir"
git -C "$dir" reset -q "$commit" || die "cannot point the clone at $commit"
/bin/sh "$(dirname "$0")/release-export.sh" "$commit" "$dir" || exit 1

url=$(git remote get-url origin) || die "cannot read origin's URL"
git -C "$dir" remote set-url origin "$url" || die "cannot set the clone's origin"
if hooks=$(git config --get core.hooksPath); then
	git -C "$dir" config core.hooksPath "$hooks" || die "cannot set the clone's core.hooksPath"
fi

for log in logs/HEAD logs/refs/heads/main; do
	from=$(git rev-parse --git-path "$log") || die "cannot find the reflog $log"
	[ ! -f "$from" ] && continue
	mkdir -p "$dir/.git/${log%/*}" && cp "$from" "$dir/.git/$log" || die "cannot copy the reflog $log"
done

if [ -f .claude/.hooks-heartbeat ]; then
	mkdir -p "$dir/.claude" && cp .claude/.hooks-heartbeat "$dir/.claude/.hooks-heartbeat" || die "cannot copy the hook heartbeat"
fi
cp Makefile.local "$dir/Makefile.local" || die "cannot copy Makefile.local"

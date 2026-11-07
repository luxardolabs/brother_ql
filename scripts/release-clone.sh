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

# Spelled out, so this machine's global config cannot rename the remote, refuse a local clone or seed
# the clone's config from a template.
git -c protocol.file.allow=always clone -q --origin origin --template= --no-checkout . "$dir" || die "cannot clone this repository into $dir"
git -C "$dir" reset -q "$commit" || die "cannot point the clone at $commit"
/bin/sh "$(dirname "$0")/release-export.sh" "$commit" "$dir" || exit 1

# The privacy gate reads every tag, and a hideRefs setting can keep one out of a clone.
tags=$(git for-each-ref refs/tags) || die "cannot read this repository's tags"
cloned=$(git -C "$dir" for-each-ref refs/tags) || die "cannot read the clone's tags"
[ "$tags" = "$cloned" ] || die "the clone does not hold this repository's tags: check transfer.hideRefs and uploadpack.hideRefs"

url=$(git remote get-url origin) || die "cannot read origin's URL"
git -C "$dir" remote set-url origin "$url" || die "cannot set the clone's origin"
# --local, because the rule asks whether this repository wired its hooks, which a global value does not.
if hooks=$(git config --local --get core.hooksPath); then
	git -C "$dir" config core.hooksPath "$hooks" || die "cannot set the clone's core.hooksPath"
fi

for log in logs/HEAD logs/refs/heads/main; do
	from=$(git rev-parse --git-path "$log") || die "cannot find the reflog $log"
	# The clone wrote reflog entries of its own, which must not stand in for a missing one.
	rm -f "$dir/.git/$log" || die "cannot clear the clone's reflog $log"
	[ -f "$from" ] || continue
	mkdir -p "$dir/.git/${log%/*}" && cp "$from" "$dir/.git/$log" || die "cannot copy the reflog $log"
done

if [ -f .claude/.hooks-heartbeat ]; then
	mkdir -p "$dir/.claude" && cp .claude/.hooks-heartbeat "$dir/.claude/.hooks-heartbeat" || die "cannot copy the hook heartbeat"
fi
cp Makefile.local "$dir/Makefile.local" || die "cannot copy Makefile.local"

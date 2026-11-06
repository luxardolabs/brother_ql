#!/bin/sh
# Writes the files of a commit to a directory, byte for byte. Usage: release-export.sh <commit> <dir>
#
# Each blob is written raw, because git archive and git checkout apply attributes and filters, which a
# repository's config can use to make the export differ from what the gate judged.
commit=$1
dir=$2

die() {
	printf 'release: %s\n' "$1" >&2
	exit 1
}

tree=$(git -c core.quotepath=off ls-tree -r "$commit") || die "cannot read the tree of $commit"
[ -n "$tree" ] || die "the tree of $commit is empty"
printf '%s\n' "$tree" | while IFS= read -r line; do
	path=${line#*"	"}
	# shellcheck disable=SC2086 # the fields of the part before the tab: mode, type, object.
	set -- ${line%%"	"*}
	case "$path" in
	\"*) exit 1 ;;
	*/*) mkdir -p "$dir/${path%/*}" || exit 1 ;;
	esac
	[ "$2" = blob ] || exit 1
	git cat-file blob "$3" >"$dir/$path" || exit 1
	if [ "$1" = 100755 ]; then chmod +x "$dir/$path" || exit 1; fi
done || die "cannot export $commit"

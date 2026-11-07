#!/bin/sh
# What the release asks of gh, in one place, so that the recipe and the command it prints for a person
# to finish by hand make the same checks.
# Usage: release-gh.sh ready
#        release-gh.sh publish <repo> <version> <notes file> <artifact dir>
#
# ready: gh's socket setting would take its token, and the account gh speaks for on github.com pushes and
# publishes, so it must be luxardolabs. gh api answers both whether gh is signed in and as whom, on every
# gh version, where `gh auth status` takes different flags from one version to the next.
# The gh that publishes must know `release create --verify-tag` (gh 2.21 or later), or a release would
# push its tag and then fail to make the Release.
# publish: asks ready again, checks the artifacts against the sums the build recorded, then creates the
# Release for the pushed tag. Run from the checkout, as the recipe and its printed command do.
run() {
	/bin/sh "$(dirname "$0")/release-run.sh" "$@"
}

die() {
	printf 'release: %s\n' "$1" >&2
	exit 1
}

ready() {
	[ -z "$(run gh config get http_unix_socket 2>/dev/null)" ] || die "gh's http_unix_socket is set, which sends gh's token to that socket: unset it"
	[ "$(run gh api --hostname github.com user --jq .login 2>/dev/null)" = luxardolabs ] || die "gh is not signed in to github.com as luxardolabs, which pushes and publishes the release: gh auth login, or gh auth switch to luxardolabs"
	run gh release create --help 2>/dev/null | grep -q -- --verify-tag || die "this gh is too old to publish the release (it has no release create --verify-tag, added in gh 2.21): upgrade gh"
}

case "${1:-}" in
ready)
	ready
	;;
publish)
	[ $# = 5 ] || die "release-gh.sh publish takes <repo> <version> <notes file> <artifact dir>"
	repo=$2 version=$3 notes=$4 dir=$5
	ready
	sums=$(git rev-parse --path-format=absolute --git-path release-dist.sha256) || die "cannot find the build's checksums"
	[ "$(ls "$dir" | wc -l)" = 2 ] && (cd "$dir" && sha256sum --check --quiet --strict "$sums" >/dev/null 2>&1) || die "the artifacts in $dir are not what the build recorded, so nothing was uploaded"
	run gh release create "v$version" --repo "$repo" --verify-tag --title "$version" --notes-file "$notes" "$dir"/brother_ql-"$version"*
	;;
*)
	die "release-gh.sh takes ready, or publish <repo> <version> <notes file> <artifact dir>"
	;;
esac

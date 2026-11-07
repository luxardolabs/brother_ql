#!/bin/sh
# Decides whether a real `make release` may go on. Usage: release-preflight.sh <make's /proc/PID directory>
# The recipe passes a dry run itself, before calling this.
#
# Prints the one word `ok` on stdout, or `refused` with the reason on stderr. The Makefile asks for a
# positive `ok`, in an expansion error, so a shell that prints nothing is refused and `.IGNORE` has no
# say. It runs under `env -i` with a fixed PATH, so an exported shell function cannot answer for the
# tools below, and it judges how make was really started: /proc holds what make cannot rewrite, while
# makefile text from `--eval` rewrites anything make's own variables hold.
#
# Stated limit: makefile text a caller supplies is code. A `$(shell ...)` in `--eval` runs before this
# does, which is no more than running git and gh by hand.
proc=$1

refuse() {
	printf 'release: %s\n' "$1" >&2
	echo refused
	exit 0
}

# Lines are arguments: a newline inside an argument becomes \001, so it cannot start a line of its own.
args=$(tr '\n\0' '\001\n' <"$proc/cmdline") || refuse "cannot read how make was started (Linux only)"
argv0=$(printf '%s\n' "$args" | head -n 1)
rest=$(printf '%s\n' "$args" | tail -n +2 | tr '\n' ' ')

# argv[0] becomes $(MAKE), which runs the gate.
case "$argv0" in
make | gmake | */make | */gmake) ;;
*) refuse "make was started under the name '$argv0', which would run the gate" ;;
esac
case "$argv0" in
*[!A-Za-z0-9_./+-]*) refuse "make's name '$argv0' holds a character that would change what \$(MAKE) runs" ;;
esac

[ "$rest" = "release " ] || refuse "takes no arguments (got: $rest). Run it bare from the checkout, and put settings in Makefile.local"

# What steers make, the recipe's tools or the shell, from the environment. An exported function replaces
# a tool in every recipe line, so all are refused except the few a login shell's profile exports, which
# name no tool a recipe runs.
[ -r "$proc/environ" ] || refuse "cannot read make's environment (Linux only)"
steering=$(grep -zoE '^(MAKEFLAGS|GNUMAKEFLAGS|MAKEFILES|MAKEOVERRIDES|MAKE|MAKE_COMMAND|\.SHELLFLAGS|LUX_REGISTRY|LUXARCH_IMAGE|LUXLINT_IMAGE|LUXAUDIT_IMAGE|TAIL_IMAGE|GIT_IDENTITY_OK|GIT_COMMITTER_NAME|GIT_COMMITTER_EMAIL|GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_GRAFT_FILE|GIT_NAMESPACE|GIT_CEILING_DIRECTORIES|GIT_DISCOVERY_ACROSS_FILESYSTEM|GIT_CONFIG|GIT_CONFIG_[A-Z_]*|GIT_REPLACE_REF_BASE|GIT_EXEC_PATH|GIT_SSH|GIT_SSH_COMMAND|GIT_SSL_[A-Z_]*|GIT_PROXY_COMMAND|GIT_ASKPASS|GIT_TRACE_REDACT|GH_REPO|GH_HOST|GH_ENTERPRISE_TOKEN|GH_CONFIG_DIR|GH_PATH|GH_DEBUG|DOCKER_HOST|DOCKER_CONTEXT|DOCKER_CONFIG|LD_[A-Z_]*|GLIBC_TUNABLES|GLOBIGNORE|BASHOPTS|SHELLOPTS|BASH_ENV|ENV|BASH_FUNC_[^=]*)=' "$proc/environ" | tr '\0' '\n' | grep -vE '^BASH_FUNC_(which|ml|module|switchml|scl|_module_raw)%%=$' | tr '\n' ' ')
[ -z "$steering" ] || refuse "the environment sets ${steering}which would steer it: unset them, and put settings in Makefile.local"

# Makefiles the dirty check below cannot see. Makefile.local is gitignored, and it holds settings only.
for other in GNUmakefile makefile; do
	[ ! -e "$other" ] || refuse "$other is read instead of the Makefile: remove it"
done
# Here in this directory, or make's include search could find another. Values are plain words, because
# make pastes them into recipes as shell text.
[ -f Makefile.local ] || refuse "there is no Makefile.local here: copy Makefile.local.example"
unknown=$(grep -vE '^[[:space:]]*(#.*)?$' Makefile.local | grep -vE '^(LUX_REGISTRY|HEAVY_[A-Z_]+)[[:space:]]*(\?|:|::)?=[[:space:]]*[A-Za-z0-9._:/-]*[[:space:]]*$' | head -n 1)
[ -z "$unknown" ] || refuse "Makefile.local may set only LUX_REGISTRY and HEAVY_*, to plain words, and holds: $unknown"

# The repository: every read must succeed, since an empty answer from a git that died reads as clean.
inside=$(git rev-parse --is-inside-work-tree 2>&1)
[ "$inside" = true ] || refuse "this is not a working tree git can read: $inside"
[ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$(pwd -P)" ] || refuse "git's working tree is not this directory: check core.worktree"
[ "$(git symbolic-ref -q HEAD)" = refs/heads/main ] || refuse "releases come from main"
replaced=$(git for-each-ref refs/replace 2>/dev/null) || refuse "cannot read refs/replace"
[ -z "$replaced" ] || refuse "refs/replace is set, so git would read other commits than the ones it pushes"
# --all, because git push goes to every URL a remote lists and plain get-url names only the first.
fetch_urls=$(git remote get-url --all origin 2>/dev/null) || refuse "there is no origin"
push_urls=$(git remote get-url --push --all origin 2>/dev/null) || refuse "there is no push URL for origin"
[ -n "$fetch_urls" ] || refuse "there is no origin"
[ -n "$push_urls" ] || refuse "there is no push URL for origin"
# Each URL must name this repository. Fetch and push may spell it differently, as a pushInsteadOf does.
names_this_repository() {
	case "$1" in
	https://github.com/luxardolabs/brother_ql | https://github.com/luxardolabs/brother_ql.git) ;;
	git@github.com:luxardolabs/brother_ql | git@github.com:luxardolabs/brother_ql.git) ;;
	ssh://git@github.com/luxardolabs/brother_ql | ssh://git@github.com/luxardolabs/brother_ql.git) ;;
	*) return 1 ;;
	esac
}
# A URL's user part can hold a token, and a refusal is read and pasted.
without_user() {
	printf '%s\n' "$1" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)?.*@#\1#; s/[?#].*//'
}
words=$IFS
IFS='
'
set -f
for url in $fetch_urls; do
	names_this_repository "$url" || refuse "origin fetches from $(without_user "$url"), and the Release goes to luxardolabs/brother_ql"
done
for url in $push_urls; do
	names_this_repository "$url" || refuse "origin pushes to $(without_user "$url"), and the Release goes to luxardolabs/brother_ql"
done
set +f
IFS=$words
for key in core.sshCommand core.gitProxy remote.origin.receivepack remote.origin.uploadpack remote.origin.vcs; do
	[ -z "$(git config --get "$key" 2>/dev/null)" ] || refuse "$key is set, which changes where or how the release is pushed"
done
# A proxy sees nothing while TLS still has to name github.com. These change whom TLS trusts, in any
# spelling, a URL-scoped one included, so a machine in the middle would get the refs and the token.
trust=$(git config --name-only --get-regexp '^http\..*(sslverify|sslcainfo|sslcapath)$' 2>/dev/null)
[ $? -le 1 ] || refuse "cannot read git's config"
[ -z "$trust" ] || refuse "$(printf '%s\n' "$trust" | head -n 1) is set, which changes whom git trusts on the push: unset it"

status=$(git -c core.fsmonitor=false status --porcelain --untracked-files=all 2>/dev/null) || refuse "git status failed: check the repository's config"
[ -z "$status" ] || refuse "the working tree is dirty: commit first"

# The bytes on disk are the bytes at HEAD. git status trusts its index and its config, which can both
# hide a change, and this checkout's Makefile and scripts are what run the release.
tree=$(git -c core.quotepath=off ls-tree -r HEAD 2>/dev/null) || refuse "cannot read the tree at HEAD"
[ -n "$tree" ] || refuse "the tree at HEAD is empty"
different=$(printf '%s\n' "$tree" | while IFS= read -r line; do
	path=${line#*"	"}
	# shellcheck disable=SC2086 # the fields of the part before the tab: mode, type, object.
	set -- ${line%%"	"*}
	case "$path" in
	\"*)
		printf 'NAME %s\n' "$path"
		break
		;;
	esac
	if [ "$2" != blob ] || [ "$1" = 120000 ] || [ "$(git hash-object --no-filters -- "$path" 2>/dev/null)" != "$3" ]; then
		printf 'BYTES %s\n' "$path"
		break
	fi
done)
case "$different" in
NAME*) refuse "the tracked name ${different#NAME } holds a tab, newline, quote or backslash: rename it" ;;
BYTES*) refuse "${different#BYTES } on disk is not a plain file holding the bytes at HEAD. An eol setting, autocrlf or a filter would rewrite it, and a release needs them off" ;;
esac

version=$(git show HEAD:VERSION 2>/dev/null)
printf '%s\n' "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || refuse "VERSION at HEAD is not X.Y.Z: '$version'"
[ "$(printf '%s\n' "$version" | wc -l)" = 1 ] || refuse "VERSION at HEAD is more than one line"
notes=$(git show HEAD:CHANGELOG.md 2>/dev/null | awk -v h="## $version " 'index($0, h) == 1 { f = 1; next } /^## / { f = 0 } f' | tr -d '[:space:]')
[ -n "$notes" ] || refuse "CHANGELOG.md at HEAD has no notes under '## $version'"
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
	refuse "tag v$version already exists"
fi

# The tag publishes its tagger, and a tag can only leave history by being deleted from origin. This is
# the fleet account of GIT_IDENTITY_OK in the Makefile, whose other address is GitHub's web committer.
tagger=$(git var GIT_COMMITTER_IDENT 2>/dev/null) || refuse "git has no identity to tag with: set the global user.name and user.email to the fleet account"
case "$tagger" in
"luxardolabs <214140984+luxardolabs@users.noreply.github.com> "*) ;;
*) refuse "the tag would carry the identity ${tagger% * *}: set the global user.name and user.email to the fleet account" ;;
esac

echo ok

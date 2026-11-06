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
steering=$(grep -zoE '^(MAKEFLAGS|GNUMAKEFLAGS|MAKEFILES|MAKEOVERRIDES|MAKE|MAKE_COMMAND|\.SHELLFLAGS|LUX_REGISTRY|LUXARCH_IMAGE|LUXLINT_IMAGE|LUXAUDIT_IMAGE|TAIL_IMAGE|GIT_IDENTITY_OK|GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_GRAFT_FILE|GIT_NAMESPACE|GIT_CEILING_DIRECTORIES|GIT_DISCOVERY_ACROSS_FILESYSTEM|GIT_CONFIG|GIT_CONFIG_[A-Z_]*|GIT_REPLACE_REF_BASE|GIT_EXEC_PATH|GH_REPO|GH_HOST|GH_ENTERPRISE_TOKEN|GH_CONFIG_DIR|DOCKER_HOST|DOCKER_CONTEXT|DOCKER_CONFIG|LD_PRELOAD|LD_LIBRARY_PATH|GLOBIGNORE|BASHOPTS|SHELLOPTS|BASH_ENV|ENV|BASH_FUNC_[^=]*)=' "$proc/environ" | tr '\0' '\n' | grep -vE '^BASH_FUNC_(which|ml|module|switchml|scl|_module_raw)%%=$' | tr '\n' ' ')
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
[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || refuse "this is not a working tree git can read"
[ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$(pwd -P)" ] || refuse "git's working tree is not this directory: check core.worktree"
[ "$(git symbolic-ref -q HEAD)" = refs/heads/main ] || refuse "releases come from main"
replaced=$(git for-each-ref refs/replace 2>/dev/null) || refuse "cannot read refs/replace"
[ -z "$replaced" ] || refuse "refs/replace is set, so git would read other commits than the ones it pushes"
fetch_url=$(git remote get-url origin 2>/dev/null) || refuse "there is no origin"
push_url=$(git remote get-url --push origin 2>/dev/null) || refuse "there is no push URL for origin"
[ "$fetch_url" = "$push_url" ] || refuse "origin pushes somewhere other than it fetches from"

status=$(git -c core.fsmonitor=false status --porcelain --untracked-files=all 2>/dev/null) || refuse "git status failed: check the repository's config"
[ -z "$status" ] || refuse "the working tree is dirty: commit first"

# The bytes on disk are the bytes at HEAD. git status trusts its index and its config, which can both
# hide a change, and the gate judges what is on disk.
tree=$(git ls-tree -r HEAD 2>/dev/null) || refuse "cannot read the tree at HEAD"
[ -n "$tree" ] || refuse "the tree at HEAD is empty"
different=$(printf '%s\n' "$tree" | while read -r mode type object path; do
	if [ "$type" != blob ] || [ "$mode" = 120000 ] || [ "$(git hash-object --no-filters "$path" 2>/dev/null)" != "$object" ]; then
		printf '%s\n' "$path"
		break
	fi
done)
[ -z "$different" ] || refuse "$different on disk is not a plain file holding what HEAD holds"

version=$(git show HEAD:VERSION 2>/dev/null)
printf '%s\n' "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || refuse "VERSION at HEAD is not X.Y.Z: '$version'"
[ "$(printf '%s\n' "$version" | wc -l)" = 1 ] || refuse "VERSION at HEAD is more than one line"
notes=$(git show HEAD:CHANGELOG.md 2>/dev/null | awk -v h="## $version " 'index($0, h) == 1 { f = 1; next } /^## / { f = 0 } f' | tr -d '[:space:]')
[ -n "$notes" ] || refuse "CHANGELOG.md at HEAD has no notes under '## $version'"
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
	refuse "tag v$version already exists"
fi

echo ok

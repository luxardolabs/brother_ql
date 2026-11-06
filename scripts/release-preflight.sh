#!/bin/sh
# Decides whether `make release` may go on. Usage: release-preflight.sh <make's /proc/PID directory>
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

case "$rest" in
"release ") dry= ;;
"-n release " | "release -n ") dry=1 ;;
*) refuse "takes no arguments (got: $rest). Run it bare from the checkout, and put settings in Makefile.local" ;;
esac

# What steers make, the recipe's tools or the shell, from the environment. An exported function replaces
# a tool in every recipe line, so all are refused except the few a login shell's profile exports, which
# name no tool a recipe runs.
[ -r "$proc/environ" ] || refuse "cannot read make's environment (Linux only)"
steering=$(grep -zoE '^(MAKEFLAGS|GNUMAKEFLAGS|MAKEFILES|MAKEOVERRIDES|MAKE|MAKE_COMMAND|\.SHELLFLAGS|LUX_REGISTRY|LUXARCH_IMAGE|LUXLINT_IMAGE|LUXAUDIT_IMAGE|TAIL_IMAGE|GIT_IDENTITY_OK|GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_GRAFT_FILE|GIT_NAMESPACE|GIT_CEILING_DIRECTORIES|GIT_DISCOVERY_ACROSS_FILESYSTEM|GIT_CONFIG|GIT_CONFIG_[A-Z_]*|GH_REPO|GH_HOST|GH_ENTERPRISE_TOKEN|DOCKER_HOST|DOCKER_CONTEXT|DOCKER_CONFIG|LD_PRELOAD|LD_LIBRARY_PATH|BASH_FUNC_[^=]*)=' "$proc/environ" | tr '\0' '\n' | grep -vE '^BASH_FUNC_(which|ml|module|scl|_module_raw)%%=$' | tr '\n' ' ')
[ -z "$steering" ] || refuse "the environment sets ${steering}which would steer it: unset them, and put settings in Makefile.local"

# A dry run publishes nothing, so the state of the tree is not its concern.
if [ -n "$dry" ]; then
	echo ok
	exit 0
fi

# Makefiles the dirty check below cannot see. Makefile.local is gitignored, and it holds settings only.
for other in GNUmakefile makefile; do
	[ ! -e "$other" ] || refuse "$other is read instead of the Makefile: remove it"
done
if [ -e Makefile.local ]; then
	unknown=$(grep -vE '^[[:space:]]*(#.*)?$' Makefile.local | grep -vE '^(LUX_REGISTRY|HEAVY_[A-Z_]+)[[:space:]]*(\?|:|::)?=[^$\\]*$' | head -n 1)
	[ -z "$unknown" ] || refuse "Makefile.local may set only LUX_REGISTRY and HEAVY_*, and holds: $unknown"
fi

# The commit to be judged and tagged.
[ "$(git symbolic-ref -q --short HEAD)" = main ] || refuse "releases come from main"
[ -z "$(git status --porcelain --untracked-files=all)" ] || refuse "the working tree is dirty: commit first"
[ -z "$(git ls-files -v | grep '^[a-zS]')" ] || refuse "a tracked file is marked assume-unchanged or skip-worktree, which hides it from the dirty check"

version=$(git show HEAD:VERSION 2>/dev/null)
printf '%s\n' "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || refuse "VERSION at HEAD is not X.Y.Z: '$version'"
[ "$(printf '%s\n' "$version" | wc -l)" = 1 ] || refuse "VERSION at HEAD is more than one line"
notes=$(git show HEAD:CHANGELOG.md 2>/dev/null | awk -v h="## $version " 'index($0, h) == 1 { f = 1; next } /^## / { f = 0 } f' | tr -d '[:space:]')
[ -n "$notes" ] || refuse "CHANGELOG.md at HEAD has no notes under '## $version'"
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
	refuse "tag v$version already exists"
fi

echo ok

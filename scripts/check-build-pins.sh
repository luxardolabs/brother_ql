#!/bin/sh
# Asks make, not the Makefile's text, what builds and tests the artifacts, and fails unless it is the
# pinned build. Run from the repository root (`make build-pins`, a leg of `make check`).
#
# `make -qp` with a goal no rule makes prints make's whole database (every variable as make will use
# it, and the one recipe make runs for each target) and runs nothing: a goal with no rule has no
# recipe, and none of the Makefile's own recipes is a goal. It reads Makefile.local as every make
# does. A text model of make misses shapes make accepts (an `=` with no spaces, a target-specific or
# pattern-specific setting, a second rule for a target, a comment indented with spaces); make's own
# database shows each of them. Fails:
# - unless TAIL_IMAGE, PIN_BUILD_TOOLS, BUILD_ARTIFACTS and CHECKOUT each have exactly one setting,
#   the Makefile's own `override` line, with no target- or pattern-specific setting anywhere;
# - unless TAIL_IMAGE is python:3.14-slim pinned by digest, PIN_BUILD_TOOLS is the hash-checked
#   install of requirements/build.txt, and BUILD_ARTIFACTS builds with it and no isolation;
# - unless the recipes make runs for `build` and `test` are scripts/build-pins/{build,test}.recipe;
# - unless the release recipe builds with BUILD_ARTIFACTS once and installs and builds nothing else;
# - unless CHECK_LEGS, as make reads it, holds build-pins and test.
# Each failure names what differs. Changing one of these recipes on purpose means changing its
# .recipe file in the same commit.
set -u

die() {
	printf 'build-pins: %s\n' "$1" >&2
	exit 1
}

[ -f Makefile ] && [ -f scripts/check-build-pins.sh ] || die "run from the repository root"
goal=__build_pins_no_such_goal__
db=$(mktemp) && err=$(mktemp) || die "cannot make a temp file"
trap 'rm -f "$db" "$err"' EXIT
trap 'exit 130' INT TERM HUP

# The parent make's flags, overrides and level would change the database, so this make gets none.
env -u MAKEFLAGS -u MFLAGS -u GNUMAKEFLAGS -u MAKEOVERRIDES -u MAKELEVEL -u MAKEFILES \
	make -qp -f Makefile "$goal" > "$db" 2> "$err"
rc=$?
[ "$rc" -eq 2 ] && [ "$(cat "$err")" = "make: *** No rule to make target '$goal'.  Stop." ] \
	|| die "make could not print its database (exit $rc): $(cat "$err")"

fail=0
bad() {
	printf 'build-pins: %s\n' "$1" >&2
	fail=1
}

# Every setting of a name in the database, with the origin line make prints before it. A global
# setting prints as `NAME = value`, a target-specific one as `target: NAME = value`, a
# pattern-specific one commented (`# NAME := value`), and a `define` as `define NAME`.
settings() {
	awk -v name="$1" '
		{
			line = $0
			sub(/^# /, "", line)
			sub(/^[^\t#:][^:]*: /, "", line)
			if (line == "define " name || index(line, name " ") == 1 && line ~ ("^" name " (:::=|::=|:=|\\+=|\\?=|!=|=)( |$)"))
				print prev " || " $0
			prev = $0
		}' "$db"
}

for name in TAIL_IMAGE PIN_BUILD_TOOLS BUILD_ARTIFACTS CHECKOUT; do
	found=$(settings "$name")
	count=$(printf '%s\n' "$found" | grep -c .)
	if [ "$count" -ne 1 ]; then
		bad "$name has $count settings, not one: $found"
		continue
	fi
	case $found in
		"# 'override' directive (from 'Makefile', line "*") || $name = "*) ;;
		*) bad "$name is not the Makefile's own override setting: $found" ;;
	esac
done

value() {
	settings "$1" | sed "s/^.* || $1 = //"
}

printf '%s\n' "$(value TAIL_IMAGE)" | grep -qxE 'python:3\.14-slim@sha256:[0-9a-f]{64}' \
	|| bad "TAIL_IMAGE is not python:3.14-slim pinned by digest: $(value TAIL_IMAGE)"
[ "$(value PIN_BUILD_TOOLS)" = "pip install -q --root-user-action=ignore --no-deps --require-hashes -r requirements/build.txt >/dev/null" ] \
	|| bad "PIN_BUILD_TOOLS is not the hash-checked install of requirements/build.txt: $(value PIN_BUILD_TOOLS)"
[ "$(value BUILD_ARTIFACTS)" = "docker run --rm --user \$(REPO_UID):\$(REPO_GID) -e HOME=/tmp -v \$(1):/repo -w /repo \$(TAIL_IMAGE) sh -c '\$(PIN_BUILD_TOOLS) && python -m build --no-isolation --outdir dist'" ] \
	|| bad "BUILD_ARTIFACTS does not build with the pinned tools and no isolation: $(value BUILD_ARTIFACTS)"

# The recipe make runs for a target: its rule's tab lines, from the Makefile.
recipe() {
	awk -v t="$1:" '
		$0 == t || index($0, t " ") == 1 { inrule = 1; next }
		inrule && /^#  recipe to execute/ { from = $0; next }
		inrule && /^\t/ { print; next }
		inrule && /^$/ { exit }
		END { if (from !~ /\(from .Makefile., line [0-9]+\):$/) print "RECIPE NOT FROM Makefile: " from }' "$db"
}

for target in build test; do
	got=$(recipe "$target")
	want=$(cat "scripts/build-pins/$target.recipe") || die "cannot read scripts/build-pins/$target.recipe"
	[ "$got" = "$want" ] || bad "the recipe make runs for $target is not scripts/build-pins/$target.recipe:
$(printf '%s\n' "$got" | diff "scripts/build-pins/$target.recipe" - | sed 's/^/  /')"
done

release=$(recipe release)
[ "$(printf '%s\n' "$release" | grep -c 'BUILD_ARTIFACTS')" -eq 1 ] \
	|| bad "the release recipe does not build with BUILD_ARTIFACTS exactly once"
printf '%s\n' "$release" | grep -qE 'pip[0-9.]* install|python[0-9.]* -m (build|pip)|hatch(ling)? build' \
	&& bad "the release recipe installs or builds outside BUILD_ARTIFACTS"

legs=$(settings CHECK_LEGS | sed 's/^.* || CHECK_LEGS [:?]*= //')
for leg in build-pins test; do
	case " $legs " in
		*" $leg "*) ;;
		*) bad "CHECK_LEGS ($legs) does not run $leg" ;;
	esac
done

[ "$fail" -eq 0 ] || exit 1
echo "build-pins: make builds and tests with the pinned tools and image"

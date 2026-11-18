#!/bin/sh
# Asks make, not the Makefile's text, what builds and tests the artifacts, and fails unless it is the
# pinned build. Run from the repository root (`make build-pins`, a leg of `make check`).
#
# `make -qp` prints make's whole database (every variable as make will use it, and the one recipe
# make runs for each target) without running a recipe of the Makefile: its goal is given its own
# empty rule with --eval, so no pattern, match-anything or .DEFAULT rule of the Makefile can make it,
# and `-o` stops make remaking Makefile or Makefile.local. The make is the one that runs this leg ($(MAKE_COMMAND),
# passed as BUILD_PINS_MAKE), read in the C locale. A text model of make misses shapes make accepts
# (an `=` with no spaces, a target-specific or pattern-specific setting, a second rule for a target,
# a comment indented with spaces); make's own database shows each of them. Fails:
# - when GNUmakefile or makefile is present, or make reads any makefile but Makefile and
#   Makefile.local, or remade one;
# - when `.IGNORE`, `.ONESHELL` or `.POSIX` is set, MAKEFLAGS gains a flag (`-i` ignores every
#   failure, as .IGNORE does), or SHELL and .SHELLFLAGS are not /bin/sh -c;
# - unless TAIL_IMAGE, PIN_BUILD_TOOLS, BUILD_ARTIFACTS and CHECKOUT each have exactly one setting,
#   the Makefile's own `override` line, with no target- or pattern-specific setting anywhere;
# - unless TAIL_IMAGE is python:3.14-slim pinned by digest, PIN_BUILD_TOOLS is the hash-checked
#   install of requirements/build.txt, BUILD_ARTIFACTS builds with it and no isolation, and
#   CHECKOUT is this checkout's directory;
# - unless the recipes make runs for `build` and `test` are scripts/build-pins/{build,test}.recipe;
# - unless the release recipe builds with BUILD_ARTIFACTS once and installs and builds nothing else;
# - unless CHECK_LEGS has one setting, the Makefile's, holding build-pins and test.
# Each failure names what differs. Changing one of these recipes on purpose means changing its
# .recipe file in the same commit.
set -u

die() {
	printf 'build-pins: %s\n' "$1" >&2
	exit 1
}

[ -f Makefile ] && [ -f scripts/check-build-pins.sh ] || die "run from the repository root"
# A plain `make` reads GNUmakefile or makefile before Makefile, so with either present the database
# below would not be the one `make build`, `make test` and `make check` use.
for other in GNUmakefile makefile; do
	[ ! -e "$other" ] || die "$other is present, and make reads it before Makefile: build from Makefile alone"
done
# The make that runs this leg, so the database is the one that make reads (on macOS, gmake).
make=${BUILD_PINS_MAKE:-make}
goal=__build_pins_database__
db=$(mktemp) && err=$(mktemp) || die "cannot make a temp file"
trap 'rm -f "$db" "$err"' EXIT
trap 'exit 130' INT TERM HUP

# The parent make's flags, overrides and level would change the database, so this make gets none.
# Its messages are read in English. `-o` keeps make from remaking the makefiles it reads.
env -u MAKEFLAGS -u MFLAGS -u GNUMAKEFLAGS -u MAKEOVERRIDES -u MAKELEVEL -u MAKEFILES \
	LC_ALL=C LANGUAGE= \
	"$make" -qp -o Makefile -o Makefile.local --eval "$goal: ;" "$goal" > "$db" 2> "$err"
rc=$?
# A warning the makefile prints while it is read is not a failure; an error is (make names itself as
# it was called, so the `***` is what marks one).
[ "$rc" -le 1 ] && ! grep -q '\*\*\* ' "$err" \
	|| die "make could not print its database (exit $rc): $(cat "$err")"
[ "$(grep -c '^# Make data base, printed on ' "$db")" -eq 1 ] \
	|| die "make printed its database more than once, so it remade a makefile it read"

fail=0
bad() {
	printf 'build-pins: %s\n' "$1" >&2
	fail=1
}

# make reads only Makefile and Makefile.local, so every setting judged below is one of theirs.
case "$(grep -E '^MAKEFILE_LIST :?= ' "$db" | sed 's/^MAKEFILE_LIST :*= *//')" in
	"Makefile" | "Makefile Makefile.local") ;;
	*) bad "make reads makefiles beyond Makefile and Makefile.local: $(grep -E '^MAKEFILE_LIST ' "$db")" ;;
esac
# Flags the makefile adds to its own MAKEFLAGS apply to every recipe (`-i` ignores every failure);
# this run's own are p and q.
flags=$(grep -E '^MAKEFLAGS :?= ' "$db" | sed 's/^MAKEFLAGS :*= *//' | awk '{print $1}')
[ "$flags" = pq ] || bad "the makefile adds make flags that apply to every recipe: MAKEFLAGS = $flags"
# Special targets that change how every recipe runs or whether its failure counts.
special=$(grep -E '^\.(IGNORE|ONESHELL|POSIX):' "$db")
[ -z "$special" ] || bad "the makefile sets special targets that change how recipes run: $special"

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
[ "$(value CHECKOUT)" = "'\$(subst ','\\'',\$(CURDIR))'" ] \
	|| bad "CHECKOUT is not this checkout's directory, quoted: $(value CHECKOUT)"

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

# The gate's legs: one setting, the Makefile's, so no target-specific value on `check` drops one.
found=$(settings CHECK_LEGS)
[ "$(printf '%s\n' "$found" | grep -c .)" -eq 1 ] || bad "CHECK_LEGS has more than one setting: $found"
case $found in
	"# makefile (from 'Makefile', line "*") || CHECK_LEGS = "*) ;;
	*) bad "CHECK_LEGS is not set by the Makefile alone: $found" ;;
esac
# Every recipe runs in /bin/sh -c, the shell the recipes are written for.
# make prints its own SHELL as `=` or `:=` by whether the caller's environment had one; a makefile's
# setting names its file.
for setting in "SHELL /bin/sh" ".SHELLFLAGS -c"; do
	name=${setting%% *}
	want=${setting#* }
	found=$(settings "$name")
	case $found in
		*"(from '"*) ok=no ;;
		*" || $name = $want" | *" || $name := $want") ok=yes ;;
		*) ok=no ;;
	esac
	[ "$(printf '%s\n' "$found" | grep -c .)" -eq 1 ] && [ "$ok" = yes ] \
		|| bad "$name is not make's own $want: $found"
done
legs=$(settings CHECK_LEGS | sed 's/^.* || CHECK_LEGS [:?]*= //')
for leg in build-pins test; do
	case " $legs " in
		*" $leg "*) ;;
		*) bad "CHECK_LEGS ($legs) does not run $leg" ;;
	esac
done

[ "$fail" -eq 0 ] || exit 1
echo "build-pins: make builds and tests with the pinned tools and image"

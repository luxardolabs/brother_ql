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

# A refusal is read and pasted, so none prints a value it was given: any can hold a token or an address.
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
*) refuse "make was started under another name, which would run the gate: run make itself" ;;
esac
case "$argv0" in
*[!A-Za-z0-9_./+-]*) refuse "make's name holds a character that would change what \$(MAKE) runs" ;;
esac

[ "$rest" = "release " ] || refuse "takes no arguments. Run it bare from the checkout, and put settings in Makefile.local"

# What steers make, the recipe's tools or the shell, from the environment. An exported function replaces
# a tool in every recipe line, so all are refused except the few a login shell's profile exports, which
# name no tool a recipe runs.
[ -r "$proc/environ" ] || refuse "cannot read make's environment (Linux only)"
steering=$(grep -zoE '^(MAKEFLAGS|GNUMAKEFLAGS|MAKEFILES|MAKEOVERRIDES|MAKE|MAKE_COMMAND|\.SHELLFLAGS|LUX_REGISTRY|LUXARCH_IMAGE|LUXLINT_IMAGE|LUXAUDIT_IMAGE|TAIL_IMAGE|GIT_IDENTITY_OK|GIT_COMMITTER_NAME|GIT_COMMITTER_EMAIL|GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_GRAFT_FILE|GIT_NAMESPACE|GIT_CEILING_DIRECTORIES|GIT_DISCOVERY_ACROSS_FILESYSTEM|GIT_CONFIG|GIT_CONFIG_[A-Z_]*|GIT_REPLACE_REF_BASE|GIT_EXEC_PATH|GIT_SSH|GIT_SSH_COMMAND|GIT_SSL_[A-Z_]*|GIT_PROXY_COMMAND|GIT_TRACE[A-Z0-9_]*|GIT_CURL_VERBOSE|GH_REPO|GH_HOST|GH_ENTERPRISE_TOKEN|GH_CONFIG_DIR|GH_PATH|GH_DEBUG|DOCKER_HOST|DOCKER_CONTEXT|DOCKER_CONFIG|LD_[A-Z_]*|GLIBC_TUNABLES|GCONV_PATH|HOSTALIASES|SSL_CERT_FILE|SSL_CERT_DIR|SSLKEYLOGFILE|GLOBIGNORE|BASHOPTS|SHELLOPTS|BASH_ENV|ENV|BASH_FUNC_[^=]*)=' "$proc/environ" | tr '\0' '\n' | grep -vE '^BASH_FUNC_(which|ml|module|switchml|scl|_module_raw)%%=$' | tr '\n' ' ')
[ -z "$steering" ] || refuse "the environment sets ${steering}which would steer it: unset them, and put settings in Makefile.local"
# The gate's legs run in the clone, where a relative path names something else.
tmpdir=$(tr '\0' '\n' <"$proc/environ" | sed -n 's/^TMPDIR=//p' | head -n 1)
case "$tmpdir" in
'' | /*) ;;
*) refuse "TMPDIR is not an absolute path: set it to one, or unset it" ;;
esac
# The command printed for a person to finish by hand quotes paths under it in single quotes.
case "$tmpdir" in
*\'*) refuse "TMPDIR holds a single quote, which would break the command printed to finish a release: use another" ;;
esac

# Makefiles the dirty check below cannot see. Makefile.local is gitignored, and it holds settings only.
for other in GNUmakefile makefile; do
	[ ! -e "$other" ] || refuse "$other is read instead of the Makefile: remove it"
done
# Here in this directory, or make's include search could find another. Values are plain words, because
# make pastes them into recipes as shell text.
[ -f Makefile.local ] || refuse "there is no Makefile.local here: copy Makefile.local.example"
unknown=$(grep -nvE '^[[:space:]]*(#.*)?$|^(LUX_REGISTRY|HEAVY_[A-Z_]+)[[:space:]]*(\?|:|::)?=[[:space:]]*[A-Za-z0-9._:/-]*[[:space:]]*$' Makefile.local | head -n 1 | cut -d: -f1)
[ -z "$unknown" ] || refuse "Makefile.local may set only LUX_REGISTRY and HEAVY_*, to plain words, and line $unknown does not"

# The repository: every read must succeed, since an empty answer from a git that died reads as clean.
inside=$(git rev-parse --is-inside-work-tree 2>&1)
[ "$inside" = true ] || refuse "this is not a working tree git can read: $inside"
[ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$(pwd -P)" ] || refuse "git's working tree is not this directory: check core.worktree"
[ "$(git symbolic-ref -q HEAD)" = refs/heads/main ] || refuse "releases come from main"
# Guards read a linked worktree's reflog and heartbeat from the main checkout, which a clone of the
# worktree would not receive, so a rule red here would go quiet there.
git_dir=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || refuse "cannot read git's directory"
common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || refuse "cannot read git's common directory"
[ "$git_dir" = "$common_dir" ] || refuse "this is a linked worktree: release from the main checkout"
# The gate's clone reads this repository by <checkout>/./.git, which an older git does not trust from the
# command line. Asked here as the clone will ask, so it stops before the gate, not after.
top=$(pwd -P)
git -c protocol.file.allow=always -c "safe.directory=$top/./.git" ls-remote "$top/." HEAD >/dev/null 2>&1 || refuse "git cannot read this repository the way the release's clone does, most often for its owner: add $top/./.git to the global safe.directory"
replaced=$(git for-each-ref refs/replace 2>/dev/null) || refuse "cannot read refs/replace"
[ -z "$replaced" ] || refuse "refs/replace is set, so git would read other commits than the ones it pushes"
# --all, because git push goes to every URL a remote lists and plain get-url names only the first.
fetch_urls=$(git remote get-url --all origin 2>/dev/null) || refuse "there is no origin"
push_urls=$(git remote get-url --push --all origin 2>/dev/null) || refuse "there is no push URL for origin"
[ -n "$fetch_urls" ] || refuse "there is no origin"
[ -n "$push_urls" ] || refuse "there is no push URL for origin"
# Each URL must name this repository over https. ssh is left out because ~/.ssh/config can send it to
# another host or run a command, and a TLS certificate has no such setting on this machine's side.
names_this_repository() {
	case "$1" in
	https://github.com/luxardolabs/brother_ql | https://github.com/luxardolabs/brother_ql.git) ;;
	*) return 1 ;;
	esac
}
# A proxy sees nothing while TLS still has to name github.com. These change whom TLS trusts, so a machine
# in the middle would get the refs and the token. Asked of the URL itself, as the push asks, so a setting
# scoped to another host does not count, and one scoped to this host or this repository does.
trusts_as_usual() {
	http=$(git config --get-urlmatch http "$1" 2>/dev/null)
	[ $? -le 1 ] || refuse "cannot read git's config"
	trust=$(printf '%s\n' "$http" | grep -E '^http\.(sslverify|sslcainfo|sslcapath|extraheader) ' | grep -vE '^http\.sslverify (true|yes|on|1)$' | head -n 1 | cut -d' ' -f1)
	[ -z "$trust" ] || refuse "$trust is set for github.com, which changes whom git trusts or what it sends on the push: unset it"
	# gh's helper declines a username other than its account's, and git then asks whatever else will answer.
	username=$(git config --get-urlmatch credential.username "$1" 2>/dev/null)
	case $? in
	0) [ "$username" = luxardolabs ] || refuse "a credential username other than luxardolabs is set for github.com, so the push would not authenticate with gh's token: unset it" ;;
	1) ;;
	*) refuse "cannot read git's config" ;;
	esac
}
# A refusal names no URL: any part of one can hold a token, and a refusal is read and pasted.
words=$IFS
IFS='
'
set -f
for url in $fetch_urls; do
	names_this_repository "$url" || refuse "origin's fetch URL is not https://github.com/luxardolabs/brother_ql, where the Release goes, and a release does not use ssh: see git remote -v"
	trusts_as_usual "$url"
done
for url in $push_urls; do
	names_this_repository "$url" || refuse "origin's push URL is not https://github.com/luxardolabs/brother_ql, where the Release goes, and a release does not use ssh: see git remote -v"
	trusts_as_usual "$url"
done
set +f
IFS=$words
# The hooks that run in the tag and the push are the commit's, from the place the guards judged.
[ "$(git config --get core.hooksPath 2>/dev/null)" = hooks ] || refuse "core.hooksPath is not hooks, so the committed hooks would not run on the push: git config core.hooksPath hooks"
stray=$(git ls-files --others -- hooks 2>/dev/null) || refuse "cannot list hooks/"
[ -z "$stray" ] || refuse "hooks/ holds a file the commit does not: git would run it in the tag or the push, so remove it"
# git skips a hook it cannot execute and only hints at it, so the scan of the push would not run.
[ -x hooks/pre-push ] || refuse "hooks/pre-push is not executable, so git would skip it on the push: chmod +x hooks/pre-push"
# Settings that run a hook or record the token's variable. A name can hold a URL, so a refusal names only
# its section.
settings=$(git config --name-only --get-regexp '^(hook|trace2)\..*$' 2>/dev/null)
[ $? -le 1 ] || refuse "cannot read git's config"
[ -z "$settings" ] || refuse "git's config holds a $(printf '%s\n' "$settings" | head -n 1 | cut -d. -f1) setting that the push would act on: unset it"
for key in core.gitProxy core.fsmonitor core.alternateRefsCommand core.askPass remote.origin.receivepack remote.origin.uploadpack remote.origin.vcs; do
	value=$(git config --get "$key" 2>/dev/null)
	# core.fsmonitor set to false turns the feature off.
	[ "$key" != core.fsmonitor ] || case "$(printf '%s' "$value" | tr 'A-Z' 'a-z')" in false | no | off | 0) value= ;; esac
	[ -z "$value" ] || refuse "$key is set, which changes where or how the release is pushed"
done
# curl reads this before git asks gh, so the push would authenticate as whoever it names: an entry for
# github.com in any case, or a default entry, which applies to every host. Read as curl reads it: a line
# starting with # is a comment, a macdef body runs to the next blank line, a value follows each keyword,
# and a quoted word runs to its closing quote, spaces and all.
if [ -f "${HOME:-}/.netrc" ] && awk '
	{ gsub(/\r/, "") }
	in_macro { if ($0 ~ /^[ \t]*$/) in_macro = 0; next }
	/^[ \t]*#/ { next }
	{
		for (i = 1; i <= NF; i++) {
			word = $i
			if (word ~ /^"/) while ((length(word) < 2 || word !~ /[^\\]"$/) && i < NF) word = word " " $(++i)
			word = tolower(word); gsub(/^"|"$/, "", word)
			if (value == "host") { if (word == "github.com") found = 1; value = ""; continue }
			if (value == "macro") { value = ""; in_macro = 1; next }
			if (value == "other") { value = ""; continue }
			if (word == "machine") value = "host"
			else if (word == "default") found = 1
			else if (word == "macdef") value = "macro"
			else if (word == "login" || word == "password" || word == "account") value = "other"
		}
	}
	END { exit !found }' "$HOME/.netrc"; then
	refuse "~/.netrc has an entry for github.com or a default one, so the push would use it instead of gh's token: remove that entry"
fi

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
printf '%s\n' "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || refuse "VERSION at HEAD is not X.Y.Z"
[ "$(printf '%s\n' "$version" | wc -l)" = 1 ] || refuse "VERSION at HEAD is more than one line"
notes=$(git show HEAD:CHANGELOG.md 2>/dev/null | awk -v h="## $version " 'index($0, h) == 1 { f = 1; next } /^## / { f = 0 } f' | tr -d '[:space:]')
[ -n "$notes" ] || refuse "CHANGELOG.md at HEAD has no notes under '## $version'"
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
	refuse "tag v$version already exists"
fi
# A version goes forward, or a merge that left VERSION behind would publish an old number on new code.
# Only release tags count: a pre-release such as v2.1.0-rc1 sorts above v2.1.0.
latest=$(git for-each-ref --sort=-v:refname --format='%(refname:strip=2)' 'refs/tags/v[0-9]*' 2>/dev/null) || refuse "cannot read the tags"
latest=$(printf '%s\n' "$latest" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
if [ -n "$latest" ] && [ "$(printf '%s\n%s\n' "${latest#v}" "$version" | sort -V | tail -n 1)" != "$version" ]; then
	refuse "VERSION $version is not above $latest, the newest release tag"
fi

# The tag publishes its tagger, and a tag can only leave history by being deleted from origin. This is
# the fleet account of GIT_IDENTITY_OK in the Makefile, whose other address is GitHub's web committer.
tagger=$(git var GIT_COMMITTER_IDENT 2>/dev/null) || refuse "git has no identity to tag with: set the global user.name and user.email to the fleet account"
case "$tagger" in
"luxardolabs <214140984+luxardolabs@users.noreply.github.com> "*) ;;
*) refuse "the tag would carry an identity other than the fleet account's (see git var GIT_COMMITTER_IDENT): set the global user.name and user.email to the fleet account" ;;
esac

echo ok

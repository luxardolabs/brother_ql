"""scripts/release-preflight.sh, run for real on a stand-in for make's /proc directory.

The suite's image has neither make nor git, so a stand-in git, first on PATH, answers as a clean
main would, and each test changes one answer.

Copyright (C) 2025 Luxardo Labs
Licensed under GPL-3.0-or-later
"""

import shlex
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "release-preflight.sh"
MAKEFILE = SCRIPT.parent.parent / "Makefile"


CLEAN_GIT = """#!/bin/sh
case "$*" in
"rev-parse --is-inside-work-tree") echo true ;;
"rev-parse --show-toplevel") pwd -P ;;
"symbolic-ref -q HEAD") echo refs/heads/main ;;
"for-each-ref refs/replace") ;;
"remote get-url --all origin" | "remote get-url --push --all origin") echo https://github.com/luxardolabs/brother_ql.git ;;
"config --get core.hooksPath") echo hooks ;;
"config --get "*) ;;
"ls-files --others -- hooks") ;;
"config --get-urlmatch http "*) exit 1 ;;
"config --get-urlmatch credential.username "*) exit 1 ;;
"-c protocol.file.allow=always -c safe.directory="*" ls-remote "*" HEAD") ;;
"config --name-only --get-regexp "*) exit 1 ;;
"for-each-ref --sort=-v:refname --format=%(refname:strip=2) refs/tags/v[0-9]*") echo v0.9.0 ;;
"rev-parse --path-format=absolute --git-dir" | "rev-parse --path-format=absolute --git-common-dir") echo /r/.git ;;
"-c core.fsmonitor=false status --porcelain --untracked-files=all") ;;
"var GIT_COMMITTER_IDENT") echo 'luxardolabs <214140984+luxardolabs@users.noreply.github.com> 1700000000 +0000' ;;
"-c core.quotepath=off ls-tree -r HEAD") printf '100644 blob aaaa\\tVERSION\\n' ;;
"hash-object --no-filters -- VERSION") echo aaaa ;;
"show HEAD:VERSION") echo 1.0.0 ;;
"show HEAD:CHANGELOG.md") printf '## 1.0.0 - x\\n\\nnotes\\n' ;;
"rev-parse -q --verify refs/tags/v1.0.0") exit 1 ;;
*) echo "unexpected: git $*" >&2; exit 99 ;;
esac
"""


def preflight(
    tmp_path,
    argv,
    environ=b"PATH=/usr/bin\x00",
    local="LUX_REGISTRY ?= registry.invalid:5000\n",
    git_answers="",
):
    """Run the preflight on a fake /proc directory, and return (stdout word, stderr).

    `git_answers` holds `case` branches tried before those of a clean main.
    """
    proc = tmp_path / "proc"
    proc.mkdir()
    (proc / "cmdline").write_bytes(b"".join(a.encode() + b"\x00" for a in argv))
    (proc / "environ").write_bytes(environ)
    if local is not None:
        (tmp_path / "Makefile.local").write_text(local)
    (tmp_path / "hooks").mkdir(exist_ok=True)
    (tmp_path / "hooks" / "pre-push").touch(mode=0o755, exist_ok=True)
    tools = tmp_path / "tools"
    tools.mkdir()
    git = tools / "git"
    git.write_text(CLEAN_GIT.replace('case "$*" in\n', f'case "$*" in\n{git_answers}'))
    git.chmod(0o755)
    done = subprocess.run(
        ["/bin/sh", str(SCRIPT), str(proc)],
        capture_output=True,
        text=True,
        cwd=tmp_path,
        check=True,
        env={"PATH": f"{tools}:/usr/bin:/bin", "LC_ALL": "C", "HOME": str(tmp_path)},
    )
    return done.stdout.strip(), done.stderr


def test_a_clean_main_with_plain_settings_passes(tmp_path):
    assert preflight(tmp_path, ["make", "release"]) == ("ok", "")


@pytest.mark.parametrize(
    ("answer", "reason"),
    [
        ('"rev-parse --is-inside-work-tree") exit 128 ;;', "working tree"),
        ('"rev-parse --show-toplevel") echo /elsewhere ;;', "core.worktree"),
        ('"symbolic-ref -q HEAD") echo refs/heads/other ;;', "main"),
        ('"symbolic-ref -q HEAD") echo heads/main ;;', "main"),
        ('"for-each-ref refs/replace") exit 128 ;;', "refs/replace"),
        ('"for-each-ref refs/replace") echo some-ref ;;', "refs/replace"),
        ('"remote get-url --all origin") exit 2 ;;', "origin"),
        (
            '"remote get-url --push --all origin") echo /sink.git ;;',
            "push URL",
        ),
        # A git that dies prints nothing, which must not read as a clean tree.
        (
            '"-c core.fsmonitor=false status --porcelain --untracked-files=all") '
            "exit 128 ;;",
            "git status failed",
        ),
        (
            '"-c core.fsmonitor=false status --porcelain --untracked-files=all") '
            "echo ' M x' ;;",
            "dirty",
        ),
        ('"-c core.quotepath=off ls-tree -r HEAD") exit 128 ;;', "tree at HEAD"),
        ('"-c core.quotepath=off ls-tree -r HEAD") ;;', "tree at HEAD"),
        ('"hash-object --no-filters -- VERSION") echo bbbb ;;', "VERSION on disk"),
        ('"hash-object --no-filters -- VERSION") exit 128 ;;', "VERSION on disk"),
        (
            "\"-c core.quotepath=off ls-tree -r HEAD\") printf '120000 blob aaaa\\tVERSION\\n' ;;",
            "VERSION on disk",
        ),
        (
            "\"-c core.quotepath=off ls-tree -r HEAD\") printf '160000 commit aaaa\\tVERSION\\n' ;;",
            "VERSION on disk",
        ),
        # A name that is only spaces must not read as no difference found.
        (
            '"-c core.quotepath=off ls-tree -r HEAD") printf \'100644 blob bbbb\\t   \\n'
            '100644 blob aaaa\\tVERSION\\n\' ;;\n"hash-object --no-filters --    ") echo cccc ;;',
            "on disk",
        ),
        (
            '"-c core.quotepath=off ls-tree -r HEAD") '
            "printf '100644 blob aaaa\\t\"a\\\\tb\"\\n' ;;",
            "rename it",
        ),
        (
            '"remote get-url --all origin" | "remote get-url --push --all origin") echo /fork.git ;;',
            "fetch URL",
        ),
        ('"remote get-url --all origin") ;;', "there is no origin"),
        ('"remote get-url --push --all origin") ;;', "no push URL"),
        # The tag publishes its tagger, so only the fleet account may make one.
        (
            "\"var GIT_COMMITTER_IDENT\") echo 'A Person <a.person@example.org> 1 +0000' ;;",
            "other than the fleet account's",
        ),
        # Another noreply address, and the fleet address behind another name.
        (
            "\"var GIT_COMMITTER_IDENT\") echo 'luxardolabs <1+other@users.noreply.github.com> 1 +0000' ;;",
            "the tag would carry",
        ),
        (
            "\"var GIT_COMMITTER_IDENT\") echo 'a.person@example.org <214140984+luxardolabs@users.noreply.github.com> 1 +0000' ;;",
            "the tag would carry",
        ),
        ('"var GIT_COMMITTER_IDENT") exit 128 ;;', "no identity"),
        # git push goes to every URL listed, so one real URL and a second must not pass.
        (
            '"remote get-url --push --all origin") '
            "printf 'https://github.com/luxardolabs/brother_ql.git\\n/sink.git\\n' ;;",
            "push URL",
        ),
        (
            '"remote get-url --all origin" | "remote get-url --push --all origin") '
            "printf 'https://github.com/luxardolabs/brother_ql.git\\n/sink.git\\n' ;;",
            "fetch URL",
        ),
        # git's own reason, such as dubious ownership, reaches the person.
        (
            '"rev-parse --is-inside-work-tree") echo "fatal: detected dubious ownership" >&2; exit 128 ;;',
            "dubious ownership",
        ),
        # A hook set in config runs inside the push and holds the token.
        (
            '"config --name-only --get-regexp "*) echo hook.x.event ;;',
            "a hook setting",
        ),
        # Records the token's variable, and diverts who the push authenticates as.
        (
            '"config --name-only --get-regexp "*) echo trace2.envvars ;;',
            "a trace2 setting",
        ),
        # gh's helper declines a username it does not hold, and git asks whatever else answers.
        (
            '"config --get-urlmatch credential.username "*) echo alice ;;',
            "credential username",
        ),
        ('"config --get-urlmatch credential.username "*) exit 128 ;;', "git's config"),
        # The clone reads this repository by <checkout>/./.git, which an older git does not trust.
        (
            '"-c protocol.file.allow=always -c safe.directory="*" ls-remote "*" HEAD") exit 128 ;;',
            "the way the release's clone does",
        ),
        # Only a release tag counts, but among those the newest one does.
        (
            '"for-each-ref --sort=-v:refname --format=%(refname:strip=2) refs/tags/v[0-9]*") '
            "printf 'v2.1.0-rc1\\nv2.0.10\\nv2.0.9\\n' ;;",
            "not above v2.0.10",
        ),
        # A version goes forward: a merge that left VERSION behind would publish an old number.
        (
            '"for-each-ref --sort=-v:refname --format=%(refname:strip=2) refs/tags/v[0-9]*") '
            "printf 'v2.0.2\\nv1.0.0\\n' ;;",
            "not above v2.0.2",
        ),
        (
            '"for-each-ref --sort=-v:refname --format=%(refname:strip=2) refs/tags/v[0-9]*") echo v1.0.10 ;;',
            "not above v1.0.10",
        ),
        (
            '"for-each-ref --sort=-v:refname --format=%(refname:strip=2) refs/tags/v[0-9]*") exit 128 ;;',
            "cannot read the tags",
        ),
        ('"config --name-only --get-regexp "*) exit 128 ;;', "git's config"),
        # The hooks that run in the push are the commit's, from where the guards look.
        ('"config --get core.hooksPath") ;;', "core.hooksPath"),
        ('"config --get core.hooksPath") echo /tmp/planted ;;', "core.hooksPath"),
        (
            '"ls-files --others -- hooks") echo hooks/reference-transaction ;;',
            "hooks/ holds a file",
        ),
        ('"ls-files --others -- hooks") exit 128 ;;', "hooks/"),
        # Each runs code inside the git that holds the token.
        ('"config --get core.fsmonitor") echo /tmp/planted ;;', "core.fsmonitor"),
        (
            '"config --get core.alternateRefsCommand") echo /tmp/planted ;;',
            "core.alternateRefsCommand",
        ),
        ('"config --get core.askPass") echo /tmp/planted ;;', "core.askPass"),
        (
            "\"config --get-urlmatch http \"*) echo 'http.extraheader Authorization: x' ;;",
            "what it sends",
        ),
        # ~/.ssh/config can send ssh to another host or run a command, so https is all a release uses.
        (
            '"remote get-url --push --all origin") echo git@github.com:luxardolabs/brother_ql.git ;;',
            "push URL",
        ),
        (
            '"remote get-url --all origin") echo ssh://git@github.com/luxardolabs/brother_ql ;;',
            "fetch URL",
        ),
        ('"config --get remote.origin.receivepack") echo evil ;;', "receivepack"),
        ('"config --get core.gitProxy") echo evil ;;', "core.gitProxy"),
        # A machine in the middle needs TLS to trust it, in any spelling of the key.
        (
            "\"config --get-urlmatch http \"*) echo 'http.sslverify false' ;;",
            "whom git trusts",
        ),
        (
            "\"config --get-urlmatch http \"*) echo 'http.sslcainfo /tmp/x.pem' ;;",
            "whom git trusts",
        ),
        (
            "\"config --get-urlmatch http \"*) echo 'http.sslcapath /tmp/x' ;;",
            "whom git trusts",
        ),
        ('"config --get-urlmatch http "*) exit 128 ;;', "git's config"),
        # Asked of the URL the push uses: a setting can be scoped to this repository's own path.
        (
            "\"config --get-urlmatch http https://github.com/luxardolabs/brother_ql.git\") echo 'http.sslverify false' ;;",
            "whom git trusts",
        ),
        (
            '"remote get-url --push --all origin") echo https://github.com/luxardolabs/brother_ql ;;\n'
            "\"config --get-urlmatch http https://github.com/luxardolabs/brother_ql\") echo 'http.sslcainfo /tmp/x.pem' ;;",
            "whom git trusts",
        ),
        # A clone of a linked worktree lacks the main checkout's reflog and heartbeat.
        (
            '"rev-parse --path-format=absolute --git-dir") echo /r/.git/worktrees/k ;;',
            "linked worktree",
        ),
        (
            '"rev-parse --path-format=absolute --git-dir") exit 128 ;;',
            "git's directory",
        ),
        ('"show HEAD:VERSION") echo 1.0.0 main ;;', "X.Y.Z"),
        ('"show HEAD:VERSION") exit 128 ;;', "X.Y.Z"),
        ('"show HEAD:CHANGELOG.md") printf "## 1.0.0 - x\\n" ;;', "no notes"),
        ('"rev-parse -q --verify refs/tags/v1.0.0") echo abc ;;', "already exists"),
    ],
)
def test_a_repository_that_is_not_a_clean_main_is_refused(tmp_path, answer, reason):
    word, said = preflight(tmp_path, ["make", "release"], git_answers=answer + "\n")
    assert word == "refused"
    assert reason in said


@pytest.mark.parametrize(
    "local",
    [
        "LUX_REGISTRY = registry.invalid; exit 0;\n",
        'HEAVY_MEMORY = 6g"; exit 0; "\n',
        "HEAVY_CPUS = `true`\n",
        "HEAVY_CPUS = $(shell true)\n",
        "LUX_REGISTRY = a b\n",
        "LUX_REGISTRY = a \\\n",
        "CHECK_LEGS := lint\n",
        ".IGNORE:\n",
        "TAIL_IMAGE := attacker/python:evil\n",
    ],
)
def test_makefile_local_may_hold_plain_settings_only(tmp_path, local):
    word, said = preflight(tmp_path, ["make", "release"], local=local)
    assert word == "refused"
    assert "Makefile.local" in said


@pytest.mark.parametrize(
    "arm",
    [
        '"remote get-url --push --all origin") echo https://github.com/luxardolabs/brother_ql ;;\n',
        '"remote get-url --all origin") echo https://github.com/luxardolabs/brother_ql ;;\n',
        # Two spellings of this repository, both pushed to.
        "\"remote get-url --push --all origin\") printf 'https://github.com/luxardolabs/brother_ql\\nhttps://github.com/luxardolabs/brother_ql.git\\n' ;;\n",
    ],
)
def test_each_spelling_of_this_repository_passes(tmp_path, arm):
    assert preflight(tmp_path, ["make", "release"], git_answers=arm) == ("ok", "")


@pytest.mark.parametrize(
    "url",
    [
        "https://tok3n@github.com/luxardolabs/brother_ql.git",
        "https://x-access-token:tok3n@github.com/luxardolabs/brother_ql.git",
        "tok3n@github.com:luxardolabs/brother_ql.git",
        # A password holding a slash, a colon in an scp-style user, and a query string.
        "https://user:tok3n/x@github.com/luxardolabs/brother_ql.git",
        "x-access-token:tok3n@github.com:luxardolabs/brother_ql.git",
        "https://github.com/luxardolabs/brother_ql.git?access_token=tok3n",
        # In the path, after a semicolon, as a host label, and as a bare scp prefix.
        "https://github.com/x-access-token/tok3n/brother_ql.git",
        "'https://github.com/luxardolabs/brother_ql.git;tok3n'",
        "https://tok3n.github.com/luxardolabs/brother_ql.git",
        "tok3n:x/evil.git",
    ],
)
def test_a_refusal_does_not_print_a_token_in_the_url(tmp_path, url):
    arm = f'"remote get-url --push --all origin") echo {url} ;;\n'
    word, said = preflight(tmp_path, ["make", "release"], git_answers=arm)
    assert word == "refused"
    assert "origin's push URL" in said
    assert "tok3n" not in said


@pytest.mark.parametrize(
    "line",
    [
        # Another host's setting never touches this push, and this one is git's default.
        "echo 'http.sslverify true'",
        "echo 'http.proxy http://proxy.invalid:3128'",
        "exit 1",
    ],
)
def test_git_settings_that_leave_tls_trust_alone_pass(tmp_path, line):
    arm = f'"config --get-urlmatch http "*) {line} ;;\n'
    assert preflight(tmp_path, ["make", "release"], git_answers=arm) == ("ok", "")


@pytest.mark.parametrize(
    "netrc",
    [
        "machine github.com login a password s3cret\n",
        # curl matches a host in any case, and a default entry applies to every host.
        "machine GitHub.com login a password s3cret\n",
        "default login a password s3cret\n",
        "machine other.invalid login a password b\ndefault\nlogin a password s3cret\n",
        "machine\tgithub.com\r\n\tlogin a\r\n\tpassword s3cret\r\n",
        # A word may be quoted, and an entry can follow a comment or a macro.
        'machine "github.com" login a password s3cret\n',
        "# for the proxy\nmachine github.com login a password s3cret\n",
        "macdef init\ncd /\n\nmachine github.com login a password s3cret\n",
        # A quoted value holding spaces and a keyword is one word to curl.
        'machine other.invalid login a password "pa ss login"\nmachine github.com login b password s3cret\n',
    ],
)
def test_a_netrc_entry_curl_would_use_for_github_is_refused(tmp_path, netrc):
    (tmp_path / ".netrc").write_text(netrc)
    word, said = preflight(tmp_path, ["make", "release"])
    assert word == "refused"
    assert ".netrc" in said
    assert "s3cret" not in said


@pytest.mark.parametrize(
    "netrc",
    [
        "machine git.internal.invalid login a password b\n",
        # api.github.com is another host to curl, and a comment is not an entry.
        "machine api.github.com login a password b\n",
        "# github.com, retired\nmachine other.invalid login a password b\n",
        # The words default and github.com where curl does not read them as an entry.
        "# default login for the corporate proxy\nmachine other.invalid login a password b\n",
        "machine other.invalid login default password github.com\n",
        "machine other.invalid login a account default password b\n",
        "machine other.invalid login a password b\nmacdef init\ndefault github.com\n\n",
    ],
)
def test_a_netrc_entry_for_another_host_passes(tmp_path, netrc):
    (tmp_path / ".netrc").write_text(netrc)
    assert preflight(tmp_path, ["make", "release"]) == ("ok", "")


@pytest.mark.parametrize(
    "arm",
    [
        # gh's helper answers for its own account, and a pre-release does not count as a release.
        '"config --get-urlmatch credential.username "*) echo luxardolabs ;;\n',
        '"for-each-ref --sort=-v:refname --format=%(refname:strip=2) refs/tags/v[0-9]*") '
        "printf 'v1.0.0-rc1\\nv0.9.0\\n' ;;\n",
        # A first release has no tag to be above.
        '"for-each-ref --sort=-v:refname --format=%(refname:strip=2) refs/tags/v[0-9]*") ;;\n',
    ],
)
def test_settings_and_tags_an_ordinary_release_has_pass(tmp_path, arm):
    assert preflight(tmp_path, ["make", "release"], git_answers=arm) == ("ok", "")


def test_a_version_refusal_does_not_print_the_file(tmp_path):
    arm = '"show HEAD:VERSION") echo ghp_s3cret ;;\n'
    word, said = preflight(tmp_path, ["make", "release"], git_answers=arm)
    assert word == "refused"
    assert "s3cret" not in said


@pytest.mark.parametrize(
    "value", ["false", "FALSE", "no", "off", "0", "true", "TRUE", "yes", "on", "1"]
)
def test_core_fsmonitor_as_a_boolean_passes(tmp_path, value):
    # true is git's own daemon, as scalar sets it, and false turns it off: neither runs a hook.
    arm = f'"config --get core.fsmonitor") echo {value} ;;\n'
    assert preflight(tmp_path, ["make", "release"], git_answers=arm) == ("ok", "")


def test_a_pre_push_hook_git_cannot_execute_is_refused(tmp_path):
    (tmp_path / "hooks").mkdir()
    (tmp_path / "hooks" / "pre-push").touch(mode=0o644)
    word, said = preflight(tmp_path, ["make", "release"])
    assert word == "refused"
    assert "hooks/pre-push is not executable" in said


@pytest.mark.parametrize(
    "argv",
    [
        ["make", "release", "GH_TOKEN=ghp_s3cret"],
        ["make", "GITHUB_TOKEN=ghp_s3cret", "release"],
        ["make", "release", "https://x:ghp_s3cret@github.com/"],
        ["make\tghp_s3cret", "release"],
    ],
)
def test_a_refusal_does_not_print_what_make_was_given(tmp_path, argv):
    word, said = preflight(tmp_path, argv)
    assert word == "refused"
    assert "s3cret" not in said


def test_a_refusal_does_not_print_the_identity_it_refuses(tmp_path):
    arm = "\"var GIT_COMMITTER_IDENT\") echo 'A Person <a.person@example.org> 1 +0000' ;;\n"
    word, said = preflight(tmp_path, ["make", "release"], git_answers=arm)
    assert word == "refused"
    assert "example.org" not in said
    assert "A Person" not in said


GH = SCRIPT.parent / "release-gh.sh"

# gh signed in to github.com as luxardolabs, with no socket set; every call is logged. The log's path is
# written in, because the allowance gh runs under drops any variable that could name it.
STAND_IN_GH = """#!/bin/sh
printf '%s\\n' "$*" >>CALLS_FILE
case "$*" in
"config get http_unix_socket") ;;
"api --hostname github.com user --jq .login") echo luxardolabs ;;
"release create --help") echo '      --verify-tag             Abort in case the git tag doesn'"'"'t already exist' ;;
"release create "*) ;;
*) echo "unexpected: gh $*" >&2; exit 99 ;;
esac
"""


def release_gh(tmp_path, *arguments, gh_answers="", sums=None):
    """Run release-gh.sh with a stand-in gh and git, and return (result, gh's calls)."""
    tools = tmp_path / "tools"
    tools.mkdir(exist_ok=True)
    (tools / "gh").write_text(
        STAND_IN_GH.replace('case "$*" in\n', f'case "$*" in\n{gh_answers}').replace(
            "CALLS_FILE", shlex.quote(str(tmp_path / "calls"))
        )
    )
    (tools / "gh").chmod(0o755)
    sums_file = tmp_path / "release-dist.sha256"
    (tools / "git").write_text(f"#!/bin/sh\necho {sums_file}\n")
    (tools / "git").chmod(0o755)
    built = tmp_path / "built"
    built.mkdir(exist_ok=True)
    (built / "brother_ql-1.0.0.tar.gz").write_bytes(b"sdist")
    (built / "brother_ql-1.0.0-py3-none-any.whl").write_bytes(b"wheel")
    listed = subprocess.run(
        ["sha256sum", "brother_ql-1.0.0.tar.gz", "brother_ql-1.0.0-py3-none-any.whl"],
        cwd=built,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    sums_file.write_text(listed if sums is None else sums)
    calls = tmp_path / "calls"
    calls.touch()
    done = subprocess.run(
        ["/bin/sh", str(GH), *arguments],
        capture_output=True,
        text=True,
        cwd=tmp_path,
        env={
            "PATH": f"{tools}:/usr/bin:/bin",
            "CALLS": str(calls),
            "HOME": str(tmp_path),
        },
    )
    return done, calls.read_text()


def test_gh_ready_when_signed_in_as_luxardolabs(tmp_path):
    done, calls = release_gh(tmp_path, "ready")
    assert done.returncode == 0, done.stderr
    # The socket is asked first: it would take the token at gh's first request.
    assert calls.splitlines() == [
        "config get http_unix_socket",
        "api --hostname github.com user --jq .login",
        "release create --help",
    ]


@pytest.mark.parametrize(
    ("answer", "reason"),
    [
        ('"config get http_unix_socket") echo /tmp/gh.sock ;;', "http_unix_socket"),
        # Another account, signed out, or an older gh that errors: the account is what is asked.
        (
            '"api --hostname github.com user --jq .login") echo someone-else ;;',
            "as luxardolabs",
        ),
        ('"api --hostname github.com user --jq .login") exit 1 ;;', "as luxardolabs"),
        # A gh without --verify-tag (Ubuntu 22.04 ships 2.4.0) would push the tag, then fail.
        (
            "\"release create --help\") echo '      --title string   Release title' ;;",
            "too old",
        ),
        ('"release create --help") exit 1 ;;', "too old"),
    ],
)
def test_gh_not_ready_is_refused(tmp_path, answer, reason):
    done, _ = release_gh(tmp_path, "ready", gh_answers=answer + "\n")
    assert done.returncode != 0
    assert reason in done.stderr


def test_publish_uploads_the_checked_artifacts_to_the_tag(tmp_path):
    notes = tmp_path / "notes"
    notes.write_text("notes")
    done, calls = release_gh(
        tmp_path,
        "publish",
        "luxardolabs/brother_ql",
        "1.0.0",
        str(notes),
        str(tmp_path / "built"),
    )
    assert done.returncode == 0, done.stderr
    create = calls.splitlines()[-1]
    assert create.startswith(
        f"release create v1.0.0 --repo luxardolabs/brother_ql --verify-tag --title 1.0.0 --notes-file {notes} "
    )
    assert create.count(str(tmp_path / "built")) == 2


@pytest.mark.parametrize(
    ("sums", "gh_answers"),
    [
        # Artifacts that are not what the build recorded.
        ("0" * 64 + "  brother_ql-1.0.0.tar.gz\n", ""),
        # gh speaking for another account by the time a person pastes the command.
        (None, '"api --hostname github.com user --jq .login") echo someone-else ;;\n'),
    ],
)
def test_publish_uploads_nothing_unless_every_check_holds(tmp_path, sums, gh_answers):
    done, calls = release_gh(
        tmp_path,
        "publish",
        "luxardolabs/brother_ql",
        "1.0.0",
        str(tmp_path / "notes"),
        str(tmp_path / "built"),
        gh_answers=gh_answers,
        sums=sums,
    )
    assert done.returncode != 0
    assert "release create v" not in calls


RUN = SCRIPT.parent / "release-run.sh"
SHOW_ENV = ["/bin/sh", "-c", 'printf "[%s]" "$@"; echo; env', "show"]


def run_under_allowance(environ, *arguments):
    """Run the allowance script, and return (exit status, arguments seen, environment seen)."""
    done = subprocess.run(
        ["/bin/sh", str(RUN), *SHOW_ENV, *arguments],
        capture_output=True,
        text=True,
        env=environ,
    )
    first, _, rest = done.stdout.partition("\n")
    seen = dict(line.split("=", 1) for line in rest.splitlines() if "=" in line)
    return done.returncode, first, seen


@pytest.mark.parametrize(
    "name",
    [
        # Print gh's token, and load a module into the process holding it.
        "GODEBUG",
        "OPENSSL_CONF",
        "OPENSSL_MODULES",
        # A name nobody listed yet is the point.
        "SOME_FUTURE_VARIABLE",
        "LD_AUDIT",
        "SSL_CERT_FILE",
        "GIT_TRACE_CURL",
        "MAKEFLAGS",
    ],
)
def test_a_name_the_allowance_does_not_list_does_not_reach_the_command(name):
    _, _, seen = run_under_allowance({"PATH": "/usr/bin:/bin", name: "x"})
    assert name not in seen


@pytest.mark.parametrize(
    "name",
    [
        "HOME",
        "XDG_CONFIG_HOME",
        "XDG_RUNTIME_DIR",
        "DBUS_SESSION_BUS_ADDRESS",
        "TMPDIR",
        "XDG_CACHE_HOME",
        "GH_TOKEN",
        "GITHUB_TOKEN",
        "HTTPS_PROXY",
        "https_proxy",
        "NO_PROXY",
    ],
)
def test_what_finds_config_keyring_token_and_proxy_reaches_the_command(name):
    value = "a value with 'quotes' and $dollars and spaces"
    _, _, seen = run_under_allowance({"PATH": "/usr/bin:/bin", name: value})
    assert seen[name] == value
    assert seen["PATH"] == "/usr/bin:/bin"


def test_a_name_that_is_not_set_stays_not_set():
    _, _, seen = run_under_allowance({"PATH": "/usr/bin:/bin"})
    assert "GH_TOKEN" not in seen
    assert "HTTPS_PROXY" not in seen


def test_the_allowance_keeps_arguments_whole_and_returns_the_status():
    rc, first, _ = run_under_allowance({"PATH": "/usr/bin:/bin"}, "a b", "c=d", "$e")
    assert rc == 0
    assert first == "[a b][c=d][$e]"
    done = subprocess.run(
        ["/bin/sh", str(RUN), "/bin/sh", "-c", "exit 7"],
        env={"PATH": "/usr/bin:/bin"},
    )
    assert done.returncode == 7


def test_a_refusal_does_not_print_a_makefile_local_value(tmp_path):
    local = "LUX_REGISTRY := r\nLUX_REGISTRY := u:tok3n@registry.invalid\n"
    word, said = preflight(tmp_path, ["make", "release"], local=local)
    assert word == "refused"
    assert "line 2" in said
    assert "tok3n" not in said


@pytest.mark.parametrize("value", [b"reltmp", b"./reltmp", b"../reltmp", b"/tmp/it's"])
def test_a_relative_tmpdir_is_refused(tmp_path, value):
    environ = b"PATH=/usr/bin\x00TMPDIR=" + value + b"\x00"
    word, said = preflight(tmp_path, ["make", "release"], environ)
    assert word == "refused"
    assert "TMPDIR" in said


@pytest.mark.parametrize("value", [b"/var/tmp", b""])
def test_an_absolute_or_empty_tmpdir_passes(tmp_path, value):
    environ = b"PATH=/usr/bin\x00TMPDIR=" + value + b"\x00"
    assert preflight(tmp_path, ["make", "release"], environ) == ("ok", "")


def test_ignored_files_do_not_stop_a_release_because_the_gate_never_reads_them(
    tmp_path,
):
    (tmp_path / "coverage.pyc").write_bytes(b"not the commit's")
    assert preflight(tmp_path, ["make", "release"]) == ("ok", "")


def test_the_tagger_is_the_fleet_account_the_privacy_gate_allows():
    allowed = next(
        line
        for line in MAKEFILE.read_text().splitlines()
        if line.startswith("GIT_IDENTITY_OK ?=")
    )
    assert r"<214140984\+luxardolabs@users\.noreply\.github\.com>" in allowed
    assert (
        '"luxardolabs <214140984+luxardolabs@users.noreply.github.com> "*'
        in SCRIPT.read_text()
    )


@pytest.mark.parametrize(
    "local",
    [
        "# a comment\n\nLUX_REGISTRY ?= docker.registry.invalid:5000\n",
        "LUX_REGISTRY := r\nHEAVY_SLOTS = 3\nHEAVY_SLOT_DIR ::= /var/tmp/s\nHEAVY_MEMORY=6g\n",
    ],
)
def test_plain_settings_pass(tmp_path, local):
    assert preflight(tmp_path, ["make", "release"], local=local)[0] == "ok"


def test_settings_from_make_s_include_search_are_refused(tmp_path):
    word, said = preflight(tmp_path, ["make", "release"], local=None)
    assert word == "refused"
    assert "no Makefile.local" in said


@pytest.mark.parametrize(
    "argv",
    [
        ["make", "release", "-i"],
        ["make", "-i", "release"],
        ["make", "release", "MAKEFLAGS=-i"],
        ["make", "release", "RELEASE_VERSION=0.9.9"],
        ["make", "release", "TAIL_IMAGE=attacker/python:evil"],
        ["make", "release", "--eval=.IGNORE: release"],
        ["make", "release", "--eval=release: MAKEFLAGS:="],
        ["make", "-f", "other.mk", "release"],
        ["make", "-C", ".", "release"],
        ["make", "-j2", "release"],
        ["make", "check", "release"],
        ["make"],
        # A newline-led argument is a variable to make, and must not read as nothing here.
        ["make", "release", "\nMAKE=true"],
        ["make", "release", "\nRELEASE_VERSION=0.9.9"],
        # The recipe passes a first argument of -n before asking this script; here it is refused.
        ["make", "-n", "release"],
        ["make", "release", "-n"],
    ],
)
def test_anything_but_the_bare_form_is_refused(tmp_path, argv):
    answer, reason = preflight(tmp_path, argv)
    assert answer == "refused"
    assert "takes no arguments" in reason


@pytest.mark.parametrize(
    "name",
    [
        "true",
        "evil/not-make",
        # A tab would reach $(MAKE) as a separator, carrying a flag or another tree.
        "make\t-ohonest",
        "make\t-Cgreen",
        "/usr/bin/make\t-i",
    ],
)
def test_a_name_that_would_change_what_the_gate_runs_is_refused(tmp_path, name):
    answer, reason = preflight(tmp_path, [name, "release"])
    assert answer == "refused"
    assert "name" in reason


@pytest.mark.parametrize(
    "variable",
    [
        b"MAKEFLAGS=-i",
        b"GNUMAKEFLAGS=--eval=x",
        b"MAKEFILES=/dev/null",
        b"MAKEOVERRIDES=X=1",
        b"MAKE=true",
        b"TAIL_IMAGE=attacker/python:evil",
        b"LUX_REGISTRY=attacker.invalid",
        b"LUXLINT_IMAGE=attacker/luxlint:1",
        b"GIT_COMMITTER_NAME=a.person",
        b"GIT_COMMITTER_EMAIL=a.person@example.org",
        b"GIT_DIR=/tmp/other",
        b"GIT_WORK_TREE=/tmp/other",
        b"GIT_CONFIG_COUNT=1",
        b"GH_REPO=attacker/other",
        b"DOCKER_HOST=tcp://attacker.invalid",
        b"LD_PRELOAD=/tmp/evil.so",
        b"LD_AUDIT=/tmp/evil.so",
        b"GLIBC_TUNABLES=x",
        b"GIT_SSL_NO_VERIFY=1",
        b"GIT_SSL_CAINFO=/tmp/evil.pem",
        b"GIT_PROXY_COMMAND=/tmp/evil",
        b"GIT_TRACE_REDACT=0",
        b"GIT_TRACE_CURL=1",
        b"GIT_CURL_VERBOSE=1",
        b"SSL_CERT_FILE=/tmp/evil.pem",
        b"SSL_CERT_DIR=/tmp/evil",
        b"SSLKEYLOGFILE=/tmp/keys",
        b"GCONV_PATH=/tmp/evil",
        b"HOSTALIASES=/tmp/evil",
        b"GH_PATH=/tmp/evil",
        b"GH_DEBUG=api",
        b"BASH_FUNC_make%%=() { :; }",
        b"GIT_REPLACE_REF_BASE=refs/other/",
        b"GIT_EXEC_PATH=/tmp/other",
        b"GH_CONFIG_DIR=/tmp/other",
        b"GLOBIGNORE=dist/*.whl",
        b"GIT_SSH=/tmp/other",
        b"GIT_SSH_COMMAND=/tmp/other",
        b"SHELLOPTS=noexec",
        b"BASH_ENV=/tmp/other",
        b"ENV=/tmp/other",
    ],
)
def test_what_steers_the_release_from_the_environment_is_refused(tmp_path, variable):
    environ = b"PATH=/usr/bin\x00" + variable + b"\x00HOME=/root\x00"
    answer, reason = preflight(tmp_path, ["make", "release"], environ)
    assert answer == "refused"
    assert variable.split(b"=")[0].decode() in reason


@pytest.mark.parametrize(
    "variable",
    [
        b"GIT_EDITOR=true",
        # A VS Code terminal sets it, and the allowance drops it from every line that authenticates.
        b"GIT_ASKPASS=/usr/share/code/resources/app/extensions/git/dist/askpass.sh",
        # A proxy sees nothing while TLS still has to name github.com.
        b"HTTPS_PROXY=http://proxy.invalid:3128",
        # The desktop sets it, and gh's own token only says who publishes.
        b"SSH_ASKPASS=/usr/libexec/openssh/ssh-askpass",
        b"GH_TOKEN=tok3n",
        b"TERM=xterm",
        b"NOTES=first line\nMAKE=true",
        b"BASH_FUNC_which%%=() { :; }",
        b"BASH_FUNC_module%%=() { :; }",
        b"BASH_FUNC_switchml%%=() { :; }",
    ],
)
def test_an_ordinary_environment_is_not_refused(tmp_path, variable):
    environ = b"PATH=/usr/bin\x00" + variable + b"\x00"
    assert preflight(tmp_path, ["make", "release"], environ) == ("ok", "")


def test_an_unreadable_proc_is_refused_not_passed(tmp_path):
    done = subprocess.run(
        ["/bin/sh", str(SCRIPT), str(tmp_path / "missing")],
        capture_output=True,
        text=True,
        cwd=tmp_path,
        check=True,
    )
    assert done.stdout.strip() == "refused"


EXPORT = SCRIPT.parent / "release-export.sh"


def export(tmp_path, listing, blobs):
    """Run the export with a stand-in git, and return (exit status, the directory written)."""
    tools = tmp_path / "tools"
    tools.mkdir()
    arms = "".join(
        f'"cat-file blob {k}") printf %s {shlex.quote(v)} ;;\n'
        for k, v in blobs.items()
    )
    (tools / "git").write_text(
        '#!/bin/sh\ncase "$*" in\n'
        f'"-c core.quotepath=off ls-tree -r abc") printf {shlex.quote(listing)} ;;\n'
        f"{arms}*) exit 128 ;;\nesac\n"
    )
    (tools / "git").chmod(0o755)
    out = tmp_path / "out"
    out.mkdir()
    done = subprocess.run(
        ["/bin/sh", str(EXPORT), "abc", str(out)],
        capture_output=True,
        text=True,
        cwd=tmp_path,
        env={"PATH": f"{tools}:/usr/bin:/bin", "LC_ALL": "C"},
    )
    return done.returncode, out


def test_the_export_writes_each_blob_with_its_mode(tmp_path):
    listing = "100644 blob a1\\tsrc/a b/x.py\\n100755 blob a2\\tscripts/run\\n"
    rc, out = export(tmp_path, listing, {"a1": "one", "a2": "two"})
    assert rc == 0
    assert (out / "src/a b/x.py").read_text() == "one"
    assert (out / "scripts/run").read_text() == "two"
    assert (out / "scripts/run").stat().st_mode & 0o100


@pytest.mark.parametrize(
    "listing",
    [
        # A blob git cannot read must stop the export, not leave a short tree.
        "100644 blob a1\\tfirst\\n100644 blob missing\\tsecond\\n",
        "160000 commit a1\\tmodule\\n",
        '100644 blob a1\\t"a\\\\tb"\\n',
        "",
    ],
)
def test_an_export_it_cannot_finish_fails(tmp_path, listing):
    assert export(tmp_path, listing, {"a1": "one"})[0] != 0


CLONE = SCRIPT.parent / "release-clone.sh"

# Answers as this checkout would: a clone writes .git into its directory, and the rest is logged.
CLONE_GIT = """#!/bin/sh
printf '%s\\n' "$*" >>"$CALLS"
case "$*" in
"-c protocol.file.allow=always -c safe.directory="*" clone -q --origin origin --template= --no-checkout . "*) mkdir -p "${12}/.git/logs" && echo clone >"${12}/.git/logs/HEAD" ;;
"-c core.quotepath=off ls-tree -r abc") printf '100644 blob a1\\tVERSION\\n' ;;
"cat-file blob a1") printf 1.0.0 ;;
"for-each-ref refs/tags") ;;
"remote get-url origin") echo https://github.com/luxardolabs/brother_ql.git ;;
"config --local --get core.hooksPath") echo hooks ;;
"rev-parse --git-path logs/HEAD") echo .git/logs/HEAD ;;
"rev-parse --git-path logs/refs/heads/main") echo .git/logs/refs/heads/main ;;
"-C "*) ;;
*) echo "unexpected: git $*" >&2; exit 99 ;;
esac
"""


def clone(tmp_path, arms=""):
    """Run the clone script on a stand-in checkout, and return (result, directory, git's calls)."""
    tools = tmp_path / "tools"
    tools.mkdir()
    (tools / "git").write_text(
        CLONE_GIT.replace('case "$*" in\n', f'case "$*" in\n{arms}')
    )
    (tools / "git").chmod(0o755)
    here = tmp_path / "here"
    (here / ".git/logs/refs/heads").mkdir(parents=True)
    (here / ".git/logs/HEAD").write_text("head history\n")
    (here / ".git/logs/refs/heads/main").write_text("main history\n")
    (here / ".claude").mkdir()
    (here / ".claude/.hooks-heartbeat").write_text("beat\n")
    (here / "Makefile.local").write_text("LUX_REGISTRY = r\n")
    (here / "coverage.pyc").write_bytes(b"not the commit's")
    out = tmp_path / "out"
    out.mkdir()
    calls = tmp_path / "calls"
    done = subprocess.run(
        ["/bin/sh", str(CLONE), "abc", str(out)],
        capture_output=True,
        text=True,
        cwd=here,
        env={"PATH": f"{tools}:/usr/bin:/bin", "LC_ALL": "C", "CALLS": str(calls)},
    )
    return done, out, calls.read_text()


def test_the_clone_holds_the_commit_and_the_state_the_guards_read(tmp_path):
    done, out, calls = clone(tmp_path)
    assert done.returncode == 0, done.stderr
    # The clone reads this repository by <checkout>/./.git, which a safe.directory naming it misses.
    here = (tmp_path / "here").resolve()
    assert f"-c safe.directory={here}/./.git clone -q" in calls
    assert (out / "VERSION").read_text() == "1.0.0"
    assert (out / ".git/logs/HEAD").read_text() == "head history\n"
    assert (out / ".git/logs/refs/heads/main").read_text() == "main history\n"
    assert (out / ".claude/.hooks-heartbeat").read_text() == "beat\n"
    assert (out / "Makefile.local").read_text() == "LUX_REGISTRY = r\n"
    assert f"-C {out} reset -q abc" in calls
    assert (
        f"-C {out} remote set-url origin https://github.com/luxardolabs/brother_ql.git"
        in calls
    )
    assert f"-C {out} config core.hooksPath hooks" in calls


def test_a_stray_file_of_the_checkout_does_not_reach_the_clone(tmp_path):
    _, out, _ = clone(tmp_path)
    assert not (out / "coverage.pyc").exists()


def test_a_checkout_without_hookspath_gives_a_clone_without_it(tmp_path):
    done, _, calls = clone(
        tmp_path, '"config --local --get core.hooksPath") exit 1 ;;\n'
    )
    assert done.returncode == 0, done.stderr
    assert " config core.hooksPath" not in calls


def test_a_checkout_without_a_reflog_gives_a_clone_without_one(tmp_path):
    arm = '"rev-parse --git-path logs/HEAD") echo .git/logs/gone ;;\n'
    done, out, _ = clone(tmp_path, arm)
    assert done.returncode == 0, done.stderr
    assert not (out / ".git/logs/HEAD").exists()


def test_a_clone_missing_one_of_the_tags_is_refused(tmp_path):
    done, _, _ = clone(tmp_path, '"for-each-ref refs/tags") echo a-personal-tag ;;\n')
    assert done.returncode != 0
    assert "hideRefs" in done.stderr


@pytest.mark.parametrize(
    "arm",
    [
        '"-c protocol.file.allow=always -c safe.directory="*) exit 128 ;;',
        '"for-each-ref refs/tags") exit 128 ;;',
        '"-C "*" for-each-ref refs/tags") exit 128 ;;',
        '"-C "*" reset -q abc") exit 128 ;;',
        '"-c core.quotepath=off ls-tree -r abc") exit 128 ;;',
        '"remote get-url origin") exit 2 ;;',
        '"-C "*" remote set-url origin "*) exit 2 ;;',
        '"-C "*" config core.hooksPath hooks") exit 2 ;;',
        '"rev-parse --git-path logs/HEAD") exit 128 ;;',
    ],
)
def test_a_clone_it_cannot_finish_fails(tmp_path, arm):
    assert clone(tmp_path, arm + "\n")[0].returncode != 0

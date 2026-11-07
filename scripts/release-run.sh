#!/bin/sh
# Runs a command that talks to GitHub or makes the tag, with only the environment named here, so no
# variable can load code into the process holding the token, change whom it trusts, or print the token.
# Usage: release-run.sh <command> [argument...]
#
# A name nothing here lists does not reach git, gh or the pre-push hook they start. What is kept finds the
# tools and their config, reaches a keyring, gives gh its token, and leaves a proxy working, which sees
# nothing while TLS still has to name github.com.
for name in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_RUNTIME_DIR \
	DBUS_SESSION_BUS_ADDRESS PATH TMPDIR LANG TERM GH_TOKEN GITHUB_TOKEN \
	HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy NO_PROXY no_proxy; do
	eval "given=\${$name+x}"
	[ -z "$given" ] || eval "set -- \"\$name=\$$name\" \"\$@\""
done
exec /usr/bin/env -i "$@"

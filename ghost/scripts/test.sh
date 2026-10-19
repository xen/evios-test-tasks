#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh -n deploy.sh scripts/verify.sh
shellcheck -s sh deploy.sh scripts/verify.sh scripts/test.sh
# Invalid arguments must fail before making any SSH connection.
expect_failure() {
    if "$@" > /dev/null 2>&1; then printf 'Expected failure: %s\n' "$*" >&2; exit 1; fi
}
expect_failure env BOOTSTRAP_TARGET=root@example.com DOMAIN='bad;command' OWNER_EMAIL=test@example.com sh deploy.sh
expect_failure env BOOTSTRAP_TARGET='root@example.com;command' DOMAIN=blog.example.com OWNER_EMAIL=test@example.com sh deploy.sh
expect_failure env BOOTSTRAP_TARGET=root@example.com DOMAIN=blog.example.com OWNER_EMAIL='bad;command' sh deploy.sh
expect_failure sh deploy.sh --unknown
printf '%s\n' 'POSIX sh syntax, ShellCheck, input rejection: passed'

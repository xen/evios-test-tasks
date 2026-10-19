#!/usr/bin/env python3
"""Run locally; POST over SSH stdin and store credentials outside Git."""
import json, os, pathlib, secrets, subprocess, sys
host = sys.argv[1]
check = subprocess.run(['ssh', '-o', 'ForwardAgent=no', host, "curl -fsS -H 'Host: ghost.dzen.dev' -H 'X-Forwarded-Proto: https' http://127.0.0.1:2368/ghost/api/admin/authentication/setup/"], capture_output=True, text=True, check=True)
if json.loads(check.stdout)['setup'][0]['status']:
    print('Owner setup already completed.')
    sys.exit(0)
secret = pathlib.Path(__file__).resolve().parent.parent / '.secrets' / 'owner.json'
secret.parent.mkdir(mode=0o700, exist_ok=True)
if secret.exists():
    owner = json.loads(secret.read_text())
else:
    owner = {'email': 'test@example.com', 'password': secrets.token_urlsafe(36)}
    fd = os.open(secret, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as f: json.dump(owner, f, indent=2)
body = {'setup': [{'name': 'Administrator', **owner, 'blogTitle': 'Ghost'}]}
cmd = ['ssh', '-o', 'ForwardAgent=no', host, "curl --fail-with-body -sS -X POST -H 'Content-Type: application/json' -H 'Host: ghost.dzen.dev' -H 'X-Forwarded-Proto: https' --data-binary @- http://127.0.0.1:2368/ghost/api/admin/authentication/setup/"]
r = subprocess.run(cmd, input=json.dumps(body), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if r.returncode:
    print('Owner setup failed; response withheld to protect credentials.', file=sys.stderr)
    sys.exit(1)
print('Owner created; credentials stored in', secret)

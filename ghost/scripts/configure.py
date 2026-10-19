#!/usr/bin/env python3
"""Run as root after Ghost CLI install. Secrets stay on this server."""
import json, os, pathlib, pwd, secrets, subprocess
root = pathlib.Path('/var/www/ghost')
config = root / 'config.production.json'
if config.exists():
    data = json.loads(config.read_text())
    if data.get('url') != 'https://ghost.dzen.dev' or data.get('server') != {'host': '127.0.0.1', 'port': 2368}:
        raise SystemExit('Existing Ghost configuration does not match this deployment')
    password = data['database']['connection']['password']
else:
    existing = subprocess.run(['mysql', '-Nse', "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='ghost'"], capture_output=True, text=True, check=True)
    if existing.stdout.strip():
        raise SystemExit('Existing ghost database without configuration; refusing to overwrite credentials')
    password = secrets.token_hex(32)
    subprocess.run(['mysql'], input=f"CREATE DATABASE ghost; CREATE USER 'ghost'@'localhost' IDENTIFIED BY '{password}'; GRANT ALL ON ghost.* TO 'ghost'@'localhost';\n", text=True, check=True)
    data = {'url': 'https://ghost.dzen.dev', 'server': {'host': '127.0.0.1', 'port': 2368}, 'database': {'client': 'mysql', 'connection': {'host': '127.0.0.1', 'user': 'ghost', 'password': password, 'database': 'ghost'}}, 'logging': {'transports': ['stdout']}, 'paths': {'contentPath': '/var/www/ghost/content'}}
    config.write_text(json.dumps(data, indent=2)+'\n')
    user = pwd.getpwnam('deploy')
    os.chown(config, user.pw_uid, user.pw_gid)
    config.chmod(0o600)
subprocess.run(['mysql'], input="SELECT 1;\n", text=True, check=True, stdout=subprocess.DEVNULL)

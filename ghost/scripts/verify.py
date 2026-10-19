#!/usr/bin/env python3
"""Verify direct IPv4 HTTPS and private-only SSH from outside the VPS."""
import concurrent.futures, json, os, socket, subprocess
host = os.environ.get('GHOST_SSH_TARGET', 'deploy@100.76.172.36')
addresses = {item[4][0] for item in socket.getaddrinfo('ghost.dzen.dev',443,type=socket.SOCK_STREAM)}
assert addresses == {'95.217.219.81'}, addresses
print('DNS resolves only to 95.217.219.81', flush=True)
for url in ['https://ghost.dzen.dev/', 'https://ghost.dzen.dev/ghost/']:
    status = subprocess.check_output(['curl','-4','-fsSL','--max-time','20','-o','/dev/null','-w','%{http_code}',url],text=True)
    assert status == '200', (url,status)
    print(url,status,flush=True)
setup = subprocess.check_output(['curl','-4','-fsS','https://ghost.dzen.dev/ghost/api/admin/authentication/setup/'],text=True)
assert json.loads(setup)['setup'][0]['status'] is True
headers = subprocess.check_output(['curl','-4','-sSI','http://ghost.dzen.dev/'],text=True)
assert '301' in headers.splitlines()[0] and 'location: https://ghost.dzen.dev/' in headers.lower()
print('Owner claimed; HTTP redirects to HTTPS',flush=True)
def probe(port):
    try:
        with socket.create_connection(('95.217.219.81',port),timeout=3):
            raise AssertionError(f'Public port open: {port}')
    except (TimeoutError, ConnectionRefusedError): pass
    return f'Public IPv4 TCP {port} unavailable'
with concurrent.futures.ThreadPoolExecutor() as pool:
    for result in pool.map(probe,[22,2368,3306,8080]): print(result,flush=True)
subprocess.run(['ssh','-o','BatchMode=yes','-o','ForwardAgent=no',host, 'set -e; sudo -n true; systemctl is-active ghost nginx mysql tailscaled certbot.timer; systemctl is-enabled ghost nginx mysql tailscaled certbot.timer; test "$(systemctl show ghost -p User --value)" = deploy; ! command -v cloudflared; test ! -e /etc/cloudflared; sudo nginx -t; sudo sshd -T | grep -E "^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|allowusers) "; sudo ufw status verbose; sudo openssl x509 -in /etc/letsencrypt/live/ghost.dzen.dev/fullchain.pem -noout -issuer -dates'],check=True)

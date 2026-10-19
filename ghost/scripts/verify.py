#!/usr/bin/env python3
"""Public checks from a machine outside the VPS, plus private SSH checks."""
import argparse, concurrent.futures, ipaddress, json, os, socket, subprocess
parser = argparse.ArgumentParser()
parser.add_argument('--edge-ip', help='Explicit Cloudflare edge IP for diagnosing stale local DNS; does not test local DNS')
args = parser.parse_args()
curl = ['curl']
if args.edge_ip:
    edge = str(ipaddress.IPv4Address(args.edge_ip))
    print('Explicit DNS override for HTTP checks:', edge, '(local DNS not verified)', flush=True)
    curl += ['--resolve',f'ghost.dzen.dev:443:{edge}','--resolve',f'ghost.dzen.dev:80:{edge}']
host = os.environ.get('GHOST_SSH_TARGET', 'deploy@100.76.172.36')
for url, status in [('https://ghost.dzen.dev/',200), ('https://ghost.dzen.dev/ghost/',200)]:
    actual = subprocess.check_output(curl+['--fail','--silent','--show-error','--location','--max-time','20','-o','/dev/null','-w','%{http_code}',url], text=True)
    assert int(actual) == status, (url,actual)
    print(url, status)
response = subprocess.check_output(curl+['-fsS','--max-time','20','https://ghost.dzen.dev/ghost/api/admin/authentication/setup/'], text=True)
assert json.loads(response)['setup'][0]['status'] is True
print('Owner setup complete')
headers = subprocess.check_output(curl+['-sSI','--max-time','20','http://ghost.dzen.dev/'], text=True)
assert '301' in headers.splitlines()[0] and 'location: https://ghost.dzen.dev/' in headers.lower()
print('HTTP redirects to HTTPS')
def probe(target):
    ip, port = target
    try:
        with socket.create_connection((ip,port),timeout=3):
            raise AssertionError(f'Public port open: {ip}:{port}')
    except (TimeoutError, ConnectionRefusedError): pass
    except OSError as error:
        # No local IPv6 route is inconclusive, never a successful firewall proof.
        if error.errno in (51,65,101,113): return f'{ip}:{port} INCONCLUSIVE: no route'
        raise
    return f'{ip}:{port} unavailable'
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
    for result in pool.map(probe,[(ip,p) for ip in ['95.217.219.81','2a01:4f9:c013:3307::1'] for p in [22,80,443,2368,3306,8080]]): print(result)
subprocess.run(['ssh','-o','BatchMode=yes','-o','ForwardAgent=no',host, 'set -e; sudo -n true; systemctl is-active ghost nginx cloudflared tailscaled mysql; systemctl is-enabled ghost nginx cloudflared tailscaled mysql; test "$(systemctl show ghost -p User --value)" = deploy; sudo nginx -t; sudo sshd -T | grep -E "^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|allowusers) "; sudo ufw status verbose'], check=True)

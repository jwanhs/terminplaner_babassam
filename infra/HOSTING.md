# Hosting

Two static sites per shop and nothing else. Appwrite Cloud runs the database,
the functions and authentication; the web server only ever serves files. That
is why this is short, and why the server needs no backups — everything on it is
rebuilt from the repo by one command.

Two ways round, depending on whether the machine that builds is the machine
that serves:

```
# One box — build and serve in the same place. No SSH, no hosting.env.
publish_local.sh <slug>   →  build, install into /srv, reload

# Separate build machine.
build_shop.sh <slug>      →  build/shops/<slug>/{customer,staff}
deploy_web.sh <slug>      →  <user>@<host>:/srv/terminplaner/<slug>/
deploy_web.sh --caddy     →  /etc/caddy/Caddyfile, validated, reloaded
```

Hostnames are generated from each shop's `BOOKING_URL` and `STAFF_URL`, the
same fields the QR codes are printed from. A poster on a wall is the one
artefact you cannot revise, so those values are read from one place rather than
kept in step by hand.

---

## 1. Prepare the server, once

The deploy path uses SSH keys. Do this before anything else — a public IP with
password authentication is found and brute-forced within hours, and any
password that has been pasted into a chat window, a ticket or an email should
be treated as already known.

### Is something already on 80 and 443?

```bash
sudo ss -tlnp '( sport = :80 or sport = :443 )'
```

If that shows Nginx Proxy Manager, Traefik or an existing nginx, **Caddy cannot
have those ports** and must not try. Set `CADDY_PORT='8080'` in
`infra/hosting.env`; Caddy then serves plain HTTP on 8080 as an internal
origin, routes by Host header, and the proxy in front keeps the certificates.
Skip to *1b*. If nothing answers, Caddy takes 80/443 itself — carry on with
*1a*.

### 1a. Caddy as the only web server

```bash
ssh-copy-id <user>@<host>          # from your machine

# Caddy from its own repository — the one in Ubuntu universe lags, and TLS
# automation is the whole reason it is here.
sudo apt update
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl rsync
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy

sudo mkdir -p /srv/terminplaner
sudo chown -R "$USER":"$USER" /srv/terminplaner

sudo systemctl enable caddy
systemctl is-active caddy || true
```

**`inactive` or `failed` here is expected when something else holds :80** — the
package ships a Caddyfile that binds it, so the service dies at install. It
comes up on the first deploy, once the generated config replaces that one. The
deploy uses `reload-or-restart` for exactly this reason: there is nothing to
reload the first time.

### 1b. Caddy behind an existing proxy

Same install as *1a* — Caddy is still what serves the files, does the SPA
fallback and sets the cache headers, which a proxy will not do for you. The
difference is what it listens on and who owns TLS.

Caddy runs as a host process; Nginx Proxy Manager runs in Docker. The container
reaches the host over the bridge, so 8080 must be bound on an address the
container can see, and firewalled everywhere else:

```bash
# Which address the container will use to reach the host.
ip -4 addr show docker0 | grep -o 'inet [0-9.]*' | cut -d' ' -f2   # usually 172.17.0.1

sudo ufw allow from 172.16.0.0/12 to any port 8080 proto tcp
sudo ufw deny 8080
```

Then in Nginx Proxy Manager, **one** proxy host covers every shop, because
Caddy routes by Host header:

| Field | Value |
| --- | --- |
| Domain Names | `*.terminplaner.haey.eu` |
| Scheme | `http` |
| Forward Hostname / IP | `172.17.0.1` (the docker0 address above) |
| Forward Port | `8080` |
| Websockets Support | off |
| Block Common Exploits | on |
| SSL | request a **wildcard** Let's Encrypt certificate |

A wildcard certificate needs a DNS challenge, which NPM does natively — pick
Cloudflare as the provider and give it an API token scoped to *Zone → DNS →
Edit* on `haey.eu`. That is the one piece of setup that makes adding a shop
need no proxy change at all.

**Do not add a proxy host per shop.** Two entries per customer is a step
somebody forgets at nine in the morning in a shop, and the wildcard removes it
entirely.

**Let the deploy user reload Caddy without a password.** `deploy_web.sh --caddy`
runs `sudo` over a non-interactive SSH session, so without this it does not
fail — it hangs on a password prompt with no terminal to read it. The three
rules match what the script actually sends, argument for argument; change one
and sudo stops matching it.

```bash
sudo tee /etc/sudoers.d/terminplaner >/dev/null <<'SUDOERS'
%DEPLOY_USER% ALL=(root) NOPASSWD: /usr/bin/cp /tmp/Caddyfile.new /etc/caddy/Caddyfile
%DEPLOY_USER% ALL=(root) NOPASSWD: /usr/bin/caddy fmt --overwrite /etc/caddy/Caddyfile
%DEPLOY_USER% ALL=(root) NOPASSWD: /usr/bin/caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
%DEPLOY_USER% ALL=(root) NOPASSWD: /usr/bin/systemctl reload-or-restart caddy
SUDOERS
sudo sed -i "s/%DEPLOY_USER%/$USER/" /etc/sudoers.d/terminplaner
sudo chmod 0440 /etc/sudoers.d/terminplaner
sudo visudo -c            # must say "parsed OK" before you log out
```

Then, in `/etc/ssh/sshd_config`:

```
PasswordAuthentication no
PermitRootLogin no
```

`sudo systemctl restart ssh`. **Keep your current session open** and confirm
you can log in from a second terminal before closing it.

Firewall: 80 and 443 open, 22 open (ideally restricted to your address).
Port 80 must stay reachable — Caddy answers the certificate challenge there,
and closing it means certificates silently stop renewing about two months
later.

```bash
cp infra/hosting.env.example infra/hosting.env   # then fill it in
```

## 1c. Flutter, when the VPS is also the build machine

Skip this if you build elsewhere. `flutter build web` runs `dart2js`, which is
the heaviest thing that will ever run on this box — check before installing,
not after:

```bash
df -h /          # Flutter plus a build wants ~5 GB free
free -h          # dart2js wants 2–3 GB of RAM
```

**Add swap if RAM is under 4 GB.** A 2 GB VPS running Docker will have the
kernel kill dart2js partway through, and the build fails with a message about
a signal rather than about memory — an hour lost to the wrong question:

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Node 22 to match CI, then Flutter — as your ordinary user, never root:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs git curl unzip xz-utils zip

git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/flutter/bin:$PATH"

flutter config --no-analytics --enable-web
flutter precache --web     # web artefacts only, not the Android toolchain
flutter doctor
```

`flutter doctor` will complain about Android and Chrome. That is correct and
does not matter: this box only ever runs `flutter build web`.

```bash
git clone -b claude/terminplaner-monetization-5hlup1 \
  https://github.com/jwanhs/terminplaner.git
cd terminplaner
flutter pub get            # rewrites pubspec.lock; google_fonts is gone now
```

### A note on logs

The generated config writes no access log, and that is deliberate rather than
an omission — see the comment above `siteBlock` in
`infra/tools/make_caddyfile.js`. Caddy's own errors and startup still go to
journald:

```bash
journalctl -u caddy -n 50 --no-pager
```

If you need request logging to debug a specific shop, add a `log` directive by
hand for the duration and take it out afterwards. Leaving it on creates a
record of visitor IP addresses, which needs a line in
`legal/Anlage-1-TOM.md`, a line in that shop's Datenschutzerklärung, and a
retention period.

## 2. DNS

One wildcard record covers every shop, so adding a customer needs no DNS work:

```
*.terminplaner.haey.eu.    A    <server-ip>
```

**Set it to DNS-only (grey cloud) if the zone is on Cloudflare.** Two reasons:

- With the orange cloud on, Cloudflare terminates TLS and sees every visitor's
  IP address. That makes Cloudflare a processor you must list in
  `legal/Anlage-2-Unterauftragsverarbeiter.md` and disclose in every shop's
  Datenschutzerklärung — which undercuts the answer you want to give when an
  owner asks where their customers' data goes.
- Whatever terminates TLS gets its certificate over HTTP-01 by default, and a
  proxied record means Cloudflare answers the challenge instead. The exception
  is the wildcard in *1b*: that uses a DNS challenge, which works either way —
  but the privacy reason above still stands on its own.

Verify before deploying, because a certificate issued against the wrong address
is slow to notice:

```bash
dig +short babassam.terminplaner.haey.eu     # expect the server IP, not a CDN
```

## 3. Prove the hosting works before trusting the build

A placeholder page separates "TLS and DNS are right" from "the Flutter build is
right". Debugging both at once, in a shop, is how a demo dies.

```bash
# on the server
mkdir -p /srv/terminplaner/babassam/customer
echo '<h1>ok</h1>' > /srv/terminplaner/babassam/customer/index.html

# from your machine
./infra/deploy_web.sh --caddy
curl -sSI https://babassam.terminplaner.haey.eu | head -1   # expect 200
```

A 523 means Cloudflare cannot reach the origin — check the grey cloud and that
the A record points at the server. A 502 from Nginx Proxy Manager means the
opposite end: NPM is fine and cannot reach Caddy, so check the forward address
and that 8080 is open to the docker bridge.

Behind a proxy, test the internal hop first — it isolates which half is wrong:

```bash
# on the server
curl -sSI -H 'Host: babassam.terminplaner.haey.eu' http://127.0.0.1:8080/ | head -1
```

## 4. Build, deploy, reload

One box:

```bash
./infra/publish_local.sh babassam
```

Separate build machine:

```bash
./infra/build_shop.sh babassam
./infra/deploy_web.sh babassam
./infra/deploy_web.sh --caddy      # only when hostnames changed
```

`--caddy` validates the config on the server before reloading. It is generated
for **all** shops at once, so a syntax error would take every shop down
together; that is what the validate step is for.

Use `--dry-run` first if you are unsure what `--delete` will remove.

## 5. Register the hostname with Appwrite

Appwrite rejects browser requests from hostnames that are not registered as a
Web platform on the project. Miss this and the app loads, then fails every
request with a CORS error that looks exactly like a broken deployment — while
you are standing in the shop.

Per shop, against that shop's project:

```bash
appwrite projects create-platform \
  --project-id "$APPWRITE_PROJECT_ID" \
  --type web --name "Customer" \
  --hostname babassam.terminplaner.haey.eu

appwrite projects create-platform \
  --project-id "$APPWRITE_PROJECT_ID" \
  --type web --name "Staff" \
  --hostname babassam-team.terminplaner.haey.eu
```

## 6. Verify

```bash
curl -sSI https://babassam.terminplaner.haey.eu | head -1
curl -sS  https://babassam.terminplaner.haey.eu | grep -o '<title>.*</title>'
```

The title must be the shop's name. If it says `babassam` for a different shop,
`brand_web_shell.js` did not run — rebuild rather than editing the server.

Check the caching rules took, or a shop will keep seeing an old build after
every fix you deploy:

```bash
curl -sSI https://babassam.terminplaner.haey.eu/flutter_service_worker.js \
  | grep -i cache-control       # expect: no-cache
```

## 7. Adding a shop

1. `cp infra/shops/_template.env infra/shops/<slug>.env`, fill it in
2. `./infra/publish_local.sh <slug>` — or `build_shop.sh` then
   `deploy_web.sh <slug> && deploy_web.sh --caddy` from a build machine
4. Register both hostnames with Appwrite (step 5)
5. Load the booking URL on a phone and **scan the printed poster** before it
   goes on a wall

No DNS change is needed — the wildcard already covers it.

---

## If the build refuses to ship

`build_shop.sh` fails the build when the output references `gstatic.com` or
`fonts.googleapis.com`:

```
REFUSING TO SHIP: the build fetches from Google at runtime.
```

The fonts are bundled and tested, so this means **CanvasKit** — and
`build_shop.sh` now handles it, so seeing this after a `git pull` means
something new. What the build does, in order:

1. Passes `--dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/`, which the
   compiled Dart honours.
2. Copies `canvaskit/` out of the SDK if the build did not emit one.
3. Rewrites any remaining gstatic URL in `flutter.js`, `flutter_bootstrap.js`
   and `main.dart.js` to the local path.

Step 3 exists because the first two are not enough. `flutter.js` and
`flutter_bootstrap.js` are copied verbatim out of the SDK and keep whatever URL
it shipped, whatever the build flags say. Whether that URL is actually reached
depends on which loader path runs — and "probably not reached" is not something
to put in a Datenschutzerklärung. Rewriting it leaves no Google address in the
artefact at all, which grep can confirm.

If the check still fires, the build prints the offending strings in context
before the guard rejects them — read those first. To look by hand:

```bash
grep -o -E '.{60}gstatic\.com.{80}' \
  build/shops/<slug>/customer/flutter.js | head -3
```

Note `gstatic.com`, not `google`: the host has no "google" in it, so grepping
for that finds nothing and reads as an all-clear.

A URL shape the rewriter does not know about belongs in
`infra/tools/localise_canvaskit.js`, with a case in its test. Do not remove the
guard — it is the only thing standing between a Flutter upgrade and a silent
disclosure.

## Cost and what happens if the box dies

The server holds nothing that is not in this repo. If it is lost: rebuild it
from step 1, run `build_shop.sh` and `deploy_web.sh` for each shop, and
everything is back — the appointments were never on it.

The bill worth watching is Appwrite, not the VPS. Each shop is its own Appwrite
project, which is what gives the tenant isolation described in
`legal/Anlage-1-TOM.md`. Check how that is priced as the project count grows;
at €29–49 per shop per month it is the number most likely to decide whether
per-shop projects stay affordable or the product needs real multi-tenancy.

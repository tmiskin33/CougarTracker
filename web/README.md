# Cougar Deadline Tracker — web

The same deadlines in a browser: one list, one calendar, no build step, no
dependencies, no server. Plain HTML, CSS, and JavaScript.

---

## Read this first: what a browser can and cannot do

This is not a limitation of the code. It is the browser's security model, and it
shapes everything below.

**Learning Suite cannot be fetched by a web page.** The same-origin policy stops
JavaScript on one site from reading another site's pages, and from touching its
cookies. There is no flag, no header, and no trick that changes this — which is
the policy working correctly, since otherwise any site you visited could read
your Learning Suite account.

**Canvas refuses cross-origin calls too.** Verified directly against
`byu.instructure.com`:

```
$ curl -i -H "Origin: https://example.com" https://byu.instructure.com/api/v1/users/self
HTTP/2 401
www-authenticate: Bearer realm="canvas-lms"
        ← no access-control-allow-origin header

$ curl -i -X OPTIONS ... https://byu.instructure.com/api/v1/users/self
HTTP/2 404
        ← no preflight support
```

No `Access-Control-Allow-Origin`, and the preflight 404s. Chrome will block the
request before Canvas ever sees it.

So the app runs in **two modes**, and which one you get depends on how you open it.

| | Opened from disk | Deployed (Vercel) | Chrome extension |
|---|---|---|---|
| View cached deadlines | ✅ | ✅ | ✅ |
| List + calendar + completion | ✅ | ✅ | ✅ |
| Import Learning Suite by pasting | ✅ | ✅ | ✅ |
| **Live Canvas sync** | ❌ blocked by CORS | ✅ via the proxy function | ✅ direct |

Two ways to get live sync. An **extension** page has `host_permissions`, which
exempts it from CORS, so it calls Canvas directly. A **deployment** includes
`api/canvas.js`, a serverless function that makes the call server-side, where
CORS does not apply — the page talks to your own domain, and your domain talks
to Canvas.

The difference matters for where your token goes. See
[Security](#security-where-your-token-goes) below.

---

## Running it as a Chrome extension (recommended)

1. Open `chrome://extensions`
2. Turn on **Developer mode** (top right)
3. Click **Load unpacked** and select this `web/` folder
4. Click the extension's toolbar icon — the app opens in a tab

Then in **Settings**, paste a Canvas access token (Canvas → Account → Settings →
**+ New Access Token**; Canvas shows it once) and press **Connect Canvas**. The
token is verified before it is saved, so a typo fails immediately.

## Deploying to Vercel

The repo is ready to deploy; the only setting that matters is the root directory.

**From the dashboard** (easiest, and it redeploys on every push):

1. [vercel.com/new](https://vercel.com/new) → import `tmiskin33/CougarTracker`
2. Set **Root Directory** to `web`
3. Framework preset: **Other**. No build command, no install step.
4. Deploy

**From the CLI:**

```bash
npm i -g vercel
cd web
vercel          # preview deployment
vercel --prod   # production
```

Either way you get a URL that works in any browser, on your phone included, with
live Canvas sync through the proxy function.

`vercel.json` sets `X-Content-Type-Options`, `Referrer-Policy: no-referrer`, and
`X-Frame-Options: DENY`. The proxy deliberately sends **no**
`Access-Control-Allow-Origin`, so only pages from your own deployment can use it
— otherwise you would be hosting an open Canvas relay for anyone who found the
URL.

**Your deployment is public by default.** The code is; your data is not — every
deadline and your token live in your browser's local storage, not on the server.
The function keeps nothing. But anyone with the URL can open the app (they would
see an empty one and need their own Canvas token). If that bothers you, Vercel's
Deployment Protection can put the whole thing behind your Vercel login.

## Running it as a plain page

Open `index.html` in Chrome, or serve the folder over HTTP. Everything works
except live Canvas sync — from `file://` there is no proxy to route through.

---

## Signing in

Each person gets their own deadlines, settings, and Canvas connection. Three
ways to say who you are, in the order that needs the least setup:

1. **Your Chrome account** — extension only. `chrome.identity` reports the
   account this Chrome profile is already signed in as. Nothing to configure,
   nothing to type.
2. **Sign in with Google** — any browser, but needs a Google OAuth client ID in
   `config.js`. Create one at *console.cloud.google.com → APIs & Services →
   Credentials → OAuth client ID → Web application*, add your deployment's URL
   under **Authorised JavaScript origins**, and paste the ID in. It is a public
   identifier, not a secret, so committing it is fine.
3. **A profile name** — type a name, get a space. No account, no network, works
   everywhere including from disk.

Switching accounts swaps the whole slice: deadlines, settings, and the Canvas
token are all namespaced per identity, and the namespace is a hash, so your
email address is not left lying around in storage keys.

### What signing in does not do

**It does not protect anything.** Every mode stores data in this browser's
`localStorage`, which anyone at this computer can read from the developer
console whether or not they are signed in — and can read *every* profile's
slice, not just their own. The Google path does not change that: the app reads
the account out of the credential to know which space to open, and deliberately
does not verify it, because with no server there is nothing to verify against
and treating an unverified claim as proof would be worse than not checking.

So this is the right tool for *"my roommate and I share a laptop and want
separate lists"*, and the wrong tool for *"my roommate must not be able to read
my list"*. The second needs the data on a server that checks who is asking,
which means a database and real session handling. On a shared machine, use
**Erase everything** when you are done — and remember a Canvas token can be
revoked from Canvas → Account → Settings at any time.

## Importing Learning Suite

Because a page cannot fetch Learning Suite, you bring the page to the app:

1. Sign in to Learning Suite and open your assignments page
2. Press <kbd>Ctrl</kbd>+<kbd>U</kbd> (view source), select all, copy
3. Paste it into **Settings → Learning Suite** and press **Read assignments**

The parsing happens in your tab. Nothing is uploaded, and no credentials are
involved — you are pasting a page you are already looking at.

If it says *"the page loaded, but no assignments could be read"*, the parser did
not recognise the layout. That paste is exactly what is needed to fix it: it is
the same markup the iOS app's parser needs, and retargeting one retargets both.

---

## Security: where your token goes

Say this plainly, because the three modes are not equivalent.

| | Token stored | Token transmitted to |
|---|---|---|
| iOS app | iOS keychain, encrypted, device only | Canvas only |
| Chrome extension | extension `localStorage`, unencrypted | Canvas only |
| Vercel deployment | browser `localStorage`, unencrypted | your Vercel function, then Canvas |

The deployment adds a hop. `api/canvas.js` forwards your `Authorization` header
to Canvas and returns the reply; it never logs, stores, or writes the token
anywhere, and the code is right there to check. But the token does pass through
a server you are renting, in memory, on every sync. **The extension does not
have this property** — if that hop bothers you, use the extension and skip the
deployment.

The iOS app keeps your Canvas token in the **iOS keychain** — encrypted, device
only, never in a backup. In a browser there is no keychain. The token goes in
`localStorage`, which means:

- anyone with access to your unlocked browser profile can read it
- it is **not** encrypted at rest
- on a shared or lab computer, do not connect Canvas here — use **Disconnect**,
  or **Erase everything**, before you walk away

A Canvas access token can read your Canvas account. Treat it like a password.
You can revoke it any time from Canvas → Account → Settings, which is the real
safety net: if you ever doubt where a token has been, revoke it and issue a new
one.

The Learning Suite paste flow involves no credentials at all, so it carries none
of this risk.

---

## Layout

```
index.html          app shell
css/app.css         neutral theme, follows the system light/dark setting
js/html-parse.js    forgiving HTML parser  ─┐
js/ls-dates.js      written-date parser     ├─ ports of the Swift originals,
js/ls-parse.js      heuristic scraper      ─┘  tested against the same fixtures
js/canvas.js        Canvas REST client
js/store.js         merge rules, grouping, per-identity localStorage
js/session.js       who is signed in, and which storage slice is theirs
config.js           optional Google OAuth client ID
js/app.js           rendering and wiring
js/sw.js            opens the app in a tab when the toolbar icon is clicked
manifest.json       Chrome extension (MV3)
api/canvas.js       Vercel function: the server-side Canvas proxy
vercel.json         security headers
test/               node --test, no dependencies
```

The three parser files are deliberate ports of
`Support/HTMLDocument.swift`, `LearningSuiteDateParser.swift`, and
`LearningSuiteParsing.swift`. They run against **the same fixture files** as the
Swift tests (`../CougarDeadlineTrackerTests/Fixtures`), so the two
implementations cannot quietly drift apart — and when real Learning Suite markup
finally arrives, one fixture update tests both.

## Tests

```
node --test web/test/*.test.js
```

No dependencies and no network. 47 tests covering the HTML parser, every written
date form, the scraper's two passes and its failure states, the merge rules —
including that a hand-set completion survives the next sync and that
"Not submitted" is never read as submitted — the proxy's rejection paths, and
that one profile's Canvas token never leaks into another's.

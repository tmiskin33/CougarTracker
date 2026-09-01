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

| | Plain web page | Chrome extension |
|---|---|---|
| View cached deadlines | ✅ | ✅ |
| List + calendar + completion | ✅ | ✅ |
| Import Learning Suite by pasting | ✅ | ✅ |
| **Live Canvas sync** | ❌ blocked by CORS | ✅ |

Loading it as an extension is the only way to get live sync, because
`host_permissions` exempts an extension's own pages from CORS. It takes about
thirty seconds to set up.

---

## Running it as a Chrome extension (recommended)

1. Open `chrome://extensions`
2. Turn on **Developer mode** (top right)
3. Click **Load unpacked** and select this `web/` folder
4. Click the extension's toolbar icon — the app opens in a tab

Then in **Settings**, paste a Canvas access token (Canvas → Account → Settings →
**+ New Access Token**; Canvas shows it once) and press **Connect Canvas**. The
token is verified before it is saved, so a typo fails immediately.

## Running it as a plain page

Open `index.html` in Chrome, or serve the folder over HTTP, or push it to GitHub
Pages. Everything works except live Canvas sync, which the browser will block.

---

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

## Security: the token is less protected here than on the phone

Say this plainly, because the two are not equivalent.

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
js/store.js         merge rules, grouping, localStorage
js/app.js           rendering and wiring
js/sw.js            opens the app in a tab when the toolbar icon is clicked
manifest.json       Chrome extension (MV3)
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
node --test web/test/parsing.test.js web/test/store.test.js
```

No dependencies and no network. Covers the HTML parser, every written date form,
the scraper's two passes and its failure states, and all the merge rules —
including that a hand-set completion survives the next sync, and that
"Not submitted" is never read as submitted.

# Cougar Deadline Tracker

Canvas and BYU Learning Suite deadlines in one list and one calendar. Native
iOS, SwiftUI, SwiftData, iOS 17+, no third-party dependencies.

---

## Read this before you build

Three things about this app are worth knowing up front.

**1. Learning Suite scraping is fragile, and that is not fixable.** BYU publishes
no API for Learning Suite. The app signs in through BYU's own login page and
reads the assignments page the way a browser would. Any redesign of that page
breaks it, without warning. Two things soften that but do not remove it:

- the parser matches on what a row *says* (a column headed "Due", text that reads
  like a date) rather than on class names, so cosmetic changes survive
- when it reads nothing, you get an explicit "Learning Suite may have changed"
  error, never a silently empty list

**2. The selectors shipped here have never seen a real Learning Suite page.**
The HTML fixtures under `CougarDeadlineTrackerTests/Fixtures/` are synthetic and
labelled as such inside the files. They pin the parser's *behaviour*; they do not
prove it reads BYU's actual markup. Retargeting it is a documented, small job —
see [Pointing the scraper at real markup](#pointing-the-scraper-at-real-markup).
Until you do that, treat Learning Suite sync as unverified.

**3. Automated reading of a BYU system may fall outside how BYU intends the site
to be used**, even with your own account and your own data. The app does only
what you could do by hand — signs in as you, fetches pages you can already open,
at the pace of a manual refresh — but that is your call to make, and the app says
so on screen during setup rather than burying it here.

Canvas has none of these problems: it is a documented REST API with a token you
issue and can revoke.

---

## What it does

**Day list.** Every deadline grouped by due date, chronological. Each row shows
its source, course, title, due time, and completion. Overdue items are marked in
red *and* by icon and label, so the distinction is not carried by colour alone.
Swipe to complete, tap for detail and a link back to the original item.

**Calendar.** Day, week, and month, switched by a segmented control. Each day
carries a count badge — dots up to three, a number past that, since nobody counts
seven dots. Tapping a day shows that day's list inline, driven by the same
grouping helper the day list uses, so a badge cannot disagree with the list it
opens.

**Two independent logins.** Canvas is a personal access token. Learning Suite is
a WebView session. Either can lapse without the other; whichever lapses is the
one you are asked to fix.

**Reminders.** Local notifications, no server: one per deadline per configured
offset (default: a day before, three hours before), plus a daily summary at a
time you pick (default 7:00 AM). Permission is requested during onboarding after
you have connected something, not on cold launch.

**Offline.** Deadlines are cached in SwiftData. The list and calendar work with
no network; refreshing needs one.

---

## Building it

Requires Xcode 15 or newer and a device running iOS 17 or newer.

1. `open CougarDeadlineTracker.xcodeproj`
2. Select the **CougarDeadlineTracker** target → Signing & Capabilities.
3. Set **Team** to your personal team (your Apple ID under Xcode → Settings →
   Accounts — a free account is enough).
4. Change **Bundle Identifier** to something unique to you, for example
   `com.yourname.cougardeadlines`. The default (`com.cougardeadlines.tracker`)
   will be refused if anyone else has registered it.
5. Plug in your iPhone, select it as the run destination, and run.
6. On the phone: Settings → General → VPN & Device Management → trust your
   developer certificate.

**Free Apple ID limits.** The signing certificate lasts 7 days. When the app
stops launching, plug the phone in and run again from Xcode — no code changes,
no data loss (the keychain and the local database survive a re-signed reinstall
of the same bundle ID). A paid Developer Program account raises that to a year
and unlocks TestFlight; nothing in this project needs one.

The background task identifier `com.cougardeadlines.refresh` is declared in
`Info.plist` and does **not** need to match your bundle identifier. Leave it
alone when you change the bundle ID.

### Tests

⌘U in Xcode, or:

```
xcodebuild test \
  -project CougarDeadlineTracker.xcodeproj \
  -scheme CougarDeadlineTracker \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

Every test runs against files on disk. None needs a network connection, a Canvas
token, or a Learning Suite session.

---

## Connecting Canvas

Canvas is a real REST API, used with a personal access token.

1. Open `byu.instructure.com` in a browser and sign in.
2. Account → Settings → **+ New Access Token**.
3. Purpose: anything ("Deadline tracker"). Leave the expiry blank.
4. Copy the token — Canvas shows it exactly once — and paste it into the app.

The token is verified against `/api/v1/users/self` before it is saved, so a typo
fails immediately instead of becoming a stored credential that fails quietly
later. It is stored in the iOS keychain, `ThisDeviceOnly`, never in UserDefaults
and never in a file. Revoke it any time from the same Canvas settings page.

A sync makes two passes:

- `GET /api/v1/users/self/todo` — everything outstanding, across every course
- `GET /api/v1/courses/:id/assignments?bucket=upcoming&include[]=submission` —
  course codes, descriptions, and submission state

The first is the backbone; if the second fails, you still get a working list.

**An alternative, if tokens turn out to be blocked:** Canvas also publishes a
per-user iCal feed (Calendar → Calendar Feed). It needs no token, but it carries
no course codes and no submission state, so completion tracking would be
manual-only. The token path is better and is what is implemented here.

---

## Connecting Learning Suite

The app opens BYU's real sign-in page in a `WKWebView`. You type your NetID
password into BYU's page and complete Duo there. The app never sees the password
— building a custom login form would both weaken that and break the moment Duo
is enforced.

What is kept: the `*.byu.edu` session cookies, in the keychain, with an assumed
expiry (8 hours, or sooner if a cookie says so). When it lapses, sync reports a
lapsed session — not a parse failure — and asks you to sign in again.

The WebView uses a non-persistent data store, so "Disconnect" genuinely clears
the session rather than leaving it in a shared cookie jar.

### Pointing the scraper at real markup

This is the step that makes Learning Suite sync trustworthy. It should take
one sitting.

1. Sign in to Learning Suite in a desktop browser and open the page that lists
   your assignments.
2. Save the page source (View Source → save, or ⌘S → "Page Source").
3. Remove anything identifying — your name, ID numbers, photo URLs. Keep the
   structure intact.
4. Replace `CougarDeadlineTrackerTests/Fixtures/learningsuite_table.html` with
   it, and update the expected titles and dates in
   `LearningSuiteParsingTests.swift` to match what is actually on the page.
5. Run the tests. If they pass, the parser already reads BYU's markup and you
   are done.
6. If they fail, you have a fixture that reproduces the failure offline. Fix one
   of two things:
   - **column or label names** — edit
     `CougarDeadlineTracker/Resources/LearningSuiteSelectors.json`. No code
     changes, no rebuild of the parsing logic.
   - **page structure** — write a new type conforming to
     `LearningSuiteParsing`. That protocol is the whole blast radius: sync,
     storage, and the UI depend only on `[ImportedDeadline]`.
7. Note the real URL path while you are there, and set it in
   Settings → Advanced → Learning Suite path (default `/student/assignments`).

---

## How it is put together

```
Model/           Deadline (SwiftData), ImportedDeadline, sync state, settings
Persistence/     Merge rules, day grouping and badge counts
Auth/            Keychain wrapper, Canvas token + Learning Suite session
Canvas/          REST client, wire types, sync service
LearningSuite/   WebView login, HTTP client, parser protocol + heuristic parser
Support/         A small forgiving HTML parser (no dependencies)
Sync/            AppModel (the app's shared state), background refresh
Notifications/   Reminder planning and the daily digest
Views/           Onboarding, day list, calendar, settings
```

Both sources produce `ImportedDeadline` values. `DeadlineStore` merges them under
three rules:

- identity is `(source, sourceItemID)`, so a re-sync updates rather than duplicates
- a hand-set completion beats whatever the source says — a swipe on a Learning
  Suite item (which reports no completion at all) survives every later sync
- items a source stops reporting are dropped only if they are still upcoming, so
  finished coursework does not vanish out of the past

### On background refresh

`BGAppRefreshTask` is opportunistic. iOS decides whether and when it runs, based
on how you use the app and the state of the phone. There is no push channel for
Canvas without a server component, and none for Learning Suite at all. The honest
description: refreshed in the background when iOS allows, and always refreshed
when the app opens or you pull down.

---

## Verifying a build by hand

Automated tests cover parsing and merging. These are the things only a device can
show you:

- [ ] Onboarding asks for Canvas and Learning Suite separately, and skipping one
      still gets you a working app on the other
- [ ] A wrong Canvas token is rejected during setup, not after
- [ ] The day list matches what Canvas actually shows as due
- [ ] The day list matches what Learning Suite actually shows as due
- [ ] Calendar badge counts equal the number of rows the day opens
- [ ] Swipe-to-complete sticks, and survives a pull-to-refresh
- [ ] A scheduled reminder actually fires (set an offset a few minutes out)
- [ ] The daily summary fires at the configured time and names the right items
- [ ] Force-quit and relaunch: still signed in, deadlines still listed, offline
- [ ] Airplane mode: list and calendar work; refresh reports a network error
- [ ] Disconnect Learning Suite, refresh: an explicit error, never a silent empty
      list
- [ ] Dynamic Type at the largest accessibility size stays readable
- [ ] VoiceOver reads a row as title, course, source, and due state
- [ ] Dark mode

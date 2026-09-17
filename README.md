# Elemora

A native iPhone and iPad app for exploring and memorizing the periodic table.

Listed on the App Store as **Elemora: Periodic Table**; **Elemora** under the
Home Screen icon; the optional paid tier is **Elemora Pro**.

The repository, the Xcode project, the scheme, the target and the bundle and
product identifiers are all still called `PeriodicPro` / `periodicpro`. That is
deliberate — Apple binds the App Store record and every subscriber receipt to
those strings, and they cannot be changed after an upload. See
[Names versus identifiers](#names-versus-identifiers).

All 118 elements, laid out correctly, in a table that fits the screen and zooms
under two fingers. Tap any element and its tile expands into a full detail page
with its real 3D structure. Fifty bundled compounds, a compound search backed
by PubChem, and a Compound Builder (beta) that looks up what you assemble. When
you are ready to remember rather than browse, five practice modes — including
quizzes you shape yourself and share as an Elemora link — turn what you read
into recall.

Built entirely in Swift and SwiftUI. No backend, no account, no third-party
dependencies. Everything about the elements works on a plane; the only network
requests the app makes are compound lookups to PubChem, and only when you ask
for one.

---

## Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Architecture](#architecture)
- [Folder structure](#folder-structure)
- [The Home Screen widget](#the-home-screen-widget)
- [How element data works](#how-element-data-works)
- [How study progress works](#how-study-progress-works)
- [Design system](#design-system)
- [Accessibility](#accessibility)
- [Testing](#testing)
- [Continuous integration](#continuous-integration)
- [TestFlight](#testflight)
- [Configuration](#configuration)
- [Screenshots](#screenshots)
- [Not in v1](#not-in-v1)

---

## What it does

### Table

The primary screen. The full 18-column table, correctly positioned, with the
lanthanide and actinide rows detached beneath it as they should be. Families are
color-coded with restrained washes, and each family also carries a distinct
glyph so the table is readable without relying on color.

Search sits in the navigation bar and matches names, symbols and atomic numbers
instantly — `oxygen`, `O` and `8` all land on the same element. Four filters sit
across the width of the screen — All, Metals, Nonmetals, Metalloids — with no
sideways scrolling and no filter button beside them. The Families card beneath
the table is the detailed filter: every family is a row you can tap, several can
be on at once, and the card shows which.

The table is pinch-to-zoom: fitted, with every column on screen, up to about
3.5× with the content under your fingers held still. Tiles gain the atomic
number and then the name as they grow, and a double tap toggles 2× and back to
fitted. There is deliberately no zoom control on screen at all — no Fit chip and
no toolbar menu; VoiceOver and Switch Control drive an invisible adjustable
element instead, so the accessible route costs nobody any chrome. Zoom and
position survive a search and a detail push, and accessibility text sizes open
already zoomed.

Search also finds compounds: the bundled catalog at once, PubChem after a
pause in typing, never for a bare atomic number.

### The expansion transition

Tapping an element is the app's signature interaction. The tile physically
becomes the detail page, using the native iOS 18 zoom navigation transition
(`matchedTransitionSource` + `navigationTransition(.zoom:)`). The hero card on
the destination deliberately mirrors the tile's shape, corner style and fill, so
the eye reads one object growing rather than two views cross-fading. Under
Reduce Motion it falls back to a standard push.

### Element detail

A large hero that scales, fades and softens as it leaves the top; cards that
rise into place as they enter the viewport; a tinted backdrop that recedes
toward the page background; and the element's name sliding into the navigation
bar once the hero is gone. All of it driven by the native scroll APIs
(`scrollTransition`, `onScrollGeometryChange`) rather than manual offset maths.

The content is deliberately restrained: an animated shell diagram with the three
facts people actually look up, a separate honest diagram of the element's
*elemental form*, four more quick facts with the rest behind a disclosure, a
short paragraph, four common uses, and a memory hook.

### Compounds and the Build tab

Fifty verified compounds ship in `compounds.json`, each with its PubChem
identifier, a curated formula, a molar mass computed from the bundled IUPAC
weights, a conservative classification where the constituents make it clear,
and a structure that says what it is: a computed conformer, a formula unit of
ions, or a representative unit cell. A compound page shows the formula, the
structure with a Ball & Stick / Space Fill switch and the same RealityKit
explorer the elements use, the facts, the elements in it, and "Data source:
PubChem". Sources: [`COMPOUND_SOURCES.md`](COMPOUND_SOURCES.md).

The **Build** tab is the Compound Builder, in beta and free for everyone. A
search field at the top finds a compound by name or formula without any
chemistry at all. Underneath it, add elements and the formula updates as you
go — and so does the identification: the bundled catalog and the on-device
cache are consulted immediately, and PubChem only once you have stopped
editing, with the previous request canceled. One match is named; several are
offered to choose between ("2 known compounds share this formula"); none is
reported as a miss and never as a discovery, and can be kept only as a
hypothetical composition. A known compound gets a real 2D structure drawn from
its own connectivity — a skeletal formula for an organic molecule, a labeled
2D structure for a small one, and a formula unit for a lattice, each labeled
for what it is.

### Study

A greeting, two status cards that lead to Progress, one strong card into a
round, and five practice tiles:

- **Flashcards** — name → symbol and symbol → name, reveal, then rate yourself
- **Quiz** — shaped before it starts: elements, compounds or both; everything,
  favorites, recently missed, not mastered, or a custom selection; family,
  state, period, group and atomic-number filters; Easy, Medium, Hard or Mixed
  question types; 5, 10, 20 or a custom length; an optional timer; shuffle on
  by default. Every session deals from a fresh seed and the deck is frozen for
  the session.
- **Match** — pair names with symbols and formulas, 6, 8 or 10 pairs
- **Identify** — a glossy model of the atom, an atomic number, or a written clue
- **Smart Review** — ten cards drawn from the elements you keep getting wrong

**My Quizzes** keeps the quizzes you save: start, edit, duplicate, rename,
delete, and share as an ordinary link —
`https://elemora.idlery.com/quiz/…` — that opens Elemora on the recipient's
device and saves the quiz for them. The quiz travels inside the link itself:
nothing is uploaded, there is no server, and only the name and the settings
are encoded. An incoming link is checked for its domain, path, size, format
version, name, and every element and compound it names before anything is
saved. There is no file, no JSON and no importer anywhere in the interface.

Identify draws its model in neutral gray until you answer. The app teaches the
family palette during onboarding, so a lavender model would narrow 118
candidates to seven before you had counted a single shell.

Rounds start with the elements you know least well. Favorites and recently
studied elements sit lower on the same screen; an element you have favorited
appears only in Favorites, so the two rows never show the same tile twice.

Every number on the screen is read from the stored progress. A new learner sees
a 0-day streak and 0% mastered, not a demo value.

### Progress

Elements mastered out of 118 on a progress ring, a streak, cards answered,
compounds in study and mastered, and a per-family breakdown. No dashboard, no
fake statistics — every number is derived from something you actually did.

### Element artwork

Each expanded element hero carries a quiet decorative layer: gold gets soft
metallic nuggets, carbon gets cut facets, mercury gets reflective beads, neon
gets a luminous bloom. Ten treatments cover all 118 elements, chosen from the
`structure`, `phase` and `category` the dataset already carries, with a short
list of named exceptions for the elements people can already picture.

It is all procedural — `Canvas`, gradients and polygons seeded from the atomic
number, so an element always looks the same and nothing is downloaded. It is
masked to a clear core so nothing is ever drawn behind the symbol, and it fades
in *after* the zoom transition settles so the shape the tile grows into is still
the plain card you tapped.

### Interactive 3D structures

Every element's structure can be opened in a RealityKit explorer: drag to turn,
pinch to zoom, double tap to reframe, tap any atom, bond or particle to select
it. Selecting brings that part to the middle of the view, dims the rest, and
opens a panel about it. Two representations are offered — the elemental form
(molecule, lattice or network) and the atom itself, where protons, neutrons and
electrons are individually selectable.

Geometry is generated from the dataset by `StructureSceneBuilder`, which is pure
Swift with no RealityKit import, so all of it is unit-tested: 118 elements, no
empty scenes, unique identifiers, bonds that reference real atoms, and geometry
normalized so nothing can render off-screen.

Scientific honesty is enforced in code and asserted by tests:

- a metallic lattice is never called a molecule, and its struts are marked as
  contacts rather than bonds, so the inspector cannot describe them as covalent
- nitrogen gets a triple bond and oxygen a double one, because that is what they
  have
- a noble gas is shown as one atom, not an invented dimer
- the atom model spreads electrons over a sphere rather than around a ring, is
  always labeled a simplification, and says outright that electrons do not
  follow fixed paths
- a nucleus too large to draw particle-for-particle says how many it is showing

The detail page shows a lightweight `Canvas` preview of the same scene rather
than standing up a 3D view inside a scrolling card.

### Elemora Pro

An optional subscription. The table, all 118 elements, search, filters,
favorites, every fact and all three original practice modes stay free.

Pro adds unlimited study rounds (free is three a day), the interactive explorer
for every element rather than six, and Smart Review. See **MONETIZATION.md** for
the product identifiers, what to create in App Store Connect, and how to test it.

---

## Requirements

| | |
| --- | --- |
| Xcode | **26.0 or newer** (App Store Connect rejects older toolchains) |
| iOS | 18.0 or newer |
| Devices | iPhone and iPad. iPhone in portrait and landscape; iPad in all four orientations |
| Swift | Swift 5 language mode on the Swift 6 toolchain |
| Dependencies | none |

iOS 18 is the floor because the zoom navigation transition, `onGeometryChange`
and `onScrollGeometryChange` are all iOS 18 APIs, and they are what the app's
two best moments are built from.

---

## Getting started

```bash
git clone <this repository>
cd PeriodicPro
open PeriodicPro.xcodeproj
```

Select the **PeriodicPro** scheme and any iPhone or iPad simulator, then ⌘R. It builds
and runs with no further setup.

To run on your own device, add your Team ID:

```bash
cp Config/Local.xcconfig.sample Config/Local.xcconfig
$EDITOR Config/Local.xcconfig     # set APP_DEVELOPMENT_TEAM
```

`Config/Local.xcconfig` is git-ignored.

---

## Architecture

Plain SwiftUI with a small amount of structure where it earns its place, and
none where it does not.

```
                 ElementCatalog                ProgressStore
              (immutable, bundled)     (@Observable, SwiftData-backed)
                        │                            │
                        └────────────┬───────────────┘
                                     │  injected once at launch
                              ┌──────┴──────┐
                              │  RootView   │
                              └──────┬──────┘
                    ┌────────────────┼────────────────┐
                 Table             Study            Progress
                    │                │
              ElementDetail    Study sessions
                                     │
                          QuizGenerator / StudyDeckBuilder
                                (pure, seeded, testable)
```

**No view models.** SwiftUI views own their own ephemeral state (`@State` for
search text, filter, disclosure). Anything that outlives a view lives in
`ProgressStore`. Adding an `ObservableObject` per screen would be ceremony
without separation — MVVM is used only where it actually improves things, which
here is nowhere.

**Two dependencies, injected at the root.** `ElementCatalog` goes into the
environment as a value type; `ProgressStore` goes in as an `@Observable` object.
Both are created once in `AppServices` at launch.

**The engine is pure.** `QuizGenerator`, `StudyDeckBuilder`, `MasteryEngine` and
`StreakCalculator` are free functions over value types, seeded by
`SeededGenerator` (SplitMix64). Same seed, same quiz — which is what makes them
testable at all.

**The store is a façade, not a passthrough.** `ProgressStore` keeps an in-memory
dictionary of value-typed snapshots that views read from, and writes through to
SwiftData. That keeps the 118-tile table from re-rendering because an unrelated
row changed.

**Performance choices worth knowing about.** The table positions its 118 tiles
absolutely inside three `ZStack`s rather than through nested stacks or a lazy
grid — 118 leaf views, no per-tile `GeometryReader`, and an exact layout at any
tile size. The whole screen uses exactly one geometry observation, on the scroll
view, to derive tile size from the screen width.

---

## Folder structure

```
PeriodicPro/
├── App/                    Entry point, service container, root tab view
├── Models/                 ChemicalElement, ElementCategory, MasteryLevel
├── Data/                   elements.json, the catalog, search and filtering
├── Persistence/            SwiftData models, container recovery, ProgressStore
├── DesignSystem/           Spacing, radii, colors, type ramp, family palette
├── Components/             ElementTile, cards, diagrams, progress ring
├── Artwork/                Procedural decorative element artwork
├── Structure3D/            Scene description, Canvas preview, RealityKit explorer
├── Store/                  StoreKit 2, entitlement, gating rules, paywall
├── StudyEngine/            Quiz and deck generation, mastery, Smart Review, RNG
├── Scanner/                Live text recognition, candidate ranking, stability
├── Notifications/          Local study reminders: preferences, planner, scheduler
├── Widgets/                The app's half of the Home Screen widget
├── WidgetShared/           Shared with the widget — see "The Home Screen widget"
├── Services/               Haptics
├── Utilities/              SF Symbol allowlist
├── Views/
│   ├── Table/              The periodic table screen, grid, filters, search
│   ├── Detail/             Element hero and detail cards
│   ├── Study/              Study hub and the four session modes
│   ├── Progress/           Mastery ring, activity, family breakdown
│   └── Onboarding/         Three skippable pages, shown once
├── Assets.xcassets/        App icon (light/dark/tinted) and accent color
└── PrivacyInfo.xcprivacy   Privacy manifest

ElemoraWidgets/             The widget extension target
├── Shared/                 A byte-identical copy of PeriodicPro/WidgetShared/
└── *.swift                 Widgets, timeline provider, App Intents, palette

PeriodicProTests/           Swift Testing unit tests
PeriodicProUITests/         XCUITest end-to-end flows
Config/                     xcconfig, Info.plist, StoreKit configuration
Tools/                      Dataset generation, validation and icon rendering
.github/workflows/          CI and TestFlight pipelines
```

---

## The Home Screen widget

Two widgets: *Quick Question*, which asks one question with four tappable
answers, and *Progress*, which shows how far through the table you are.

The constraint that shapes the whole design is that a widget runs in its own
process and **must never write the learner's progress**. Two writers on one
SwiftData store is how progress gets corrupted. So:

```
widget                          app group container            app
------                          -------------------            ---
draws from ──────────────────►  widget-snapshot.json  ◄──────── writes
appends to ──────────────────►  widget-events.jsonl   ◄──────── drains, then clears
owns ────────────────────────►  widget-state.json
```

`WidgetBridge` (in the app) merges the log into `ProgressStore` on launch, on
every foreground, and on the way to the background. Every event carries a UUID
minted at the tap, and the app keeps a bounded ledger of the ones it has
counted, so a retried App Intent, a duplicated line and a re-read of a log that
was never cleared all count exactly once. An answer counts on the day it was
given rather than the day it was merged.

### Why the shared file exists twice

`PeriodicPro/WidgetShared/ElemoraSharedStore.swift` and
`ElemoraWidgets/Shared/ElemoraSharedStore.swift` are the same file. The project
uses file-system synchronized groups, where a folder belongs to a target; two
targets sharing one folder is expressible and fragile to hand-maintain, and a
serialization contract that silently diverges between a widget and its app is
the exact bug this arrangement exists to prevent.

`Tools/check_widget_shared.py` compares them byte for byte and fails the build
on any difference, naming the first line that disagrees and printing the `cp`
that fixes it. It also checks the App Group identifier in the source against
both entitlements files, the extension point identifier that decides whether
iOS loads the widget at all, and the widget's written-out palette against the
app icon's.

**If you edit one, copy it to the other.** That is the whole rule.

---

## How element data works

The dataset is **bundled, not fetched**. `PeriodicPro/Data/elements.json` holds
one record per element with its identity, position, physical properties and
editorial copy. It is loaded once at launch into `ElementCatalog`, which builds
lookup indexes by atomic number and symbol.

Structure is generated, not typed. `Tools/backbone.py` derives every element's
family, group, period, block and table coordinates from its atomic number, so a
hand edit can never move an element on the table. `Tools/build_elements.py`
merges the authored fields onto that backbone, and the backbone always wins.

Two validators guard it:

- `Tools/validate_elements.py` — runs on every push, on Linux, in seconds
- `PeriodicProTests/ElementDataTests.swift` — the same checks inside the app's
  own test bundle

Between them they assert 118 unique elements with contiguous atomic numbers,
unique symbols and table positions, shell counts that sum to Z and respect the
2n² limit, electron configurations that parse and account for exactly Z
electrons (including the twenty well-known anomalies), correct room-temperature
phases, plausible and correctly ordered physical properties, and complete
editorial copy within its length budgets.

Sources, conventions and the reasoning behind contested classifications are in
[`DATA_SOURCES.md`](DATA_SOURCES.md).

To change the data:

```bash
$EDITOR PeriodicPro/Data/elements.json
python3 Tools/validate_elements.py        # must pass before committing
```

---

## How study progress works

Four levels per element, stored as an integer:

```
0  Not Started   →   1  Learning   →   2  Familiar   →   3  Mastered
```

A correct answer moves one step up, capped at Mastered. An incorrect answer
moves one step down, but never below Learning — attempting an element always
counts as having started it. Three correct answers take an element from
untouched to mastered; one miss costs a step.

Deliberately **not** spaced repetition. A small honest score is enough to order
the study queue (least familiar first) and to drive the Progress screen, and it
is something a learner can actually reason about. Real scheduling can come later
without changing the storage.

Everything is stored locally in SwiftData:

| Model | Holds |
| --- | --- |
| `ElementProgressRecord` | favorite flag, mastery level, correct/incorrect counts, last reviewed |
| `RecentSearchRecord` | the last eight search terms |
| `StudyDayRecord` | one row per day you answered a card, which drives the streak |

If the store cannot be opened, `PersistenceController` deletes it and retries
once; if that fails too it falls back to an in-memory container, and if
SwiftData cannot even provide one, `ProgressStore` runs entirely from memory.
No failure path ends in a crash, and the Progress screen says plainly when
progress was rebuilt, is not being saved, or when a write failed — the app
never tells a silent lie about saved data.

---

## Design system

Everything visual comes from tokens in `DesignSystem/`:

- **Spacing** — an 8-point rhythm with a named screen margin and section gap
- **Radii** — 5 for a table tile, 14 for a control, 20 for a card, 28 for a hero
- **Shadows** — three levels, all soft enough that stacked cards stay light
- **Colors** — semantic surfaces (canvas, surface, hairline, three text levels)
  plus a ten-family palette. Each family exposes three roles: a saturated accent
  for glyphs and strokes, a pale fill for tiles, and a readable on-fill color
- **Type** — system fonts throughout, so Dynamic Type, tracking and optical
  sizing behave the way iOS expects

Dark mode is hand-tuned, not inverted. Surfaces keep separation from the
background instead of collapsing into flat gray, and family fills become
low-luminance versions of the same hue so an element still reads as belonging to
its family.

Haptics are sparse on purpose: selecting an element, favoriting, revealing a
card, and the outcome of an answer. Nothing fires on scroll or navigation.

---

## Accessibility

- Every element tile carries a spoken label — name, symbol spelled out letter by
  letter, atomic number, family — so VoiceOver does not try to pronounce "Na"
- Family is never communicated by color alone: each carries a distinct glyph
- Reduce Motion replaces the zoom transition with a standard push, stops the
  electrons, and disables every scroll transition
- Accessibility text sizes switch the table to the comfortable layout
  automatically, so tiles never become unreadably small
- Controls outside the fitted table meet the 44-point target. Inside it, hit
  areas tile the grid with no dead space between them, so a slightly-off tap
  still lands on the element it looks like — and the comfortable layout is one
  tap away, or automatic at accessibility text sizes
- Shell diagrams describe themselves ("5 electron shells, shell 1: 2, …")
- Accessibility identifiers on every interactive element, which is what the UI
  tests query
- Contrast is measured, not assumed: `Tools/check_contrast.py` reads the real
  values out of the design system and checks all 94 color pairings the UI draws
  — semantic text on both surfaces, white labels on the accent, each family's
  symbol on its tile, each family accent on the canvas, and each nucleus symbol
  on its accent — against WCAG AA in both appearances. It runs in CI, and it is
  what caught ten light-mode failures in the first palette

---

## Testing

```bash
# Everything that runs without a Mac: dataset validation, Swift hygiene and
# SF Symbol coverage, Xcode project structure, table layout at three device
# widths, and the US English spelling gate.
./Tools/verify.sh

# Everything
xcodebuild test \
  -project PeriodicPro.xcodeproj \
  -scheme PeriodicPro \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Unit tests only
xcodebuild test \
  -project PeriodicPro.xcodeproj -scheme PeriodicPro \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PeriodicProTests

# Dataset validation, no Mac required
python3 Tools/validate_elements.py
```

**Unit tests** (Swift Testing) cover the 118-element dataset, search ranking,
filtering, quiz and deck generation determinism, mastery transitions, streak
arithmetic, the progress store against an in-memory SwiftData container,
presentation formatting, artwork resolution for all 118 elements, structure
scene geometry and chemistry, Smart Review ranking, and every free/Pro gating
combination. Nothing in the test suite contacts StoreKit — entitlement is
injected.

**Local checks** (`Tools/verify.sh`) run on any machine in a couple of seconds
and are the same checks CI's `validate-data` job runs. They catch the class of
mistake that is otherwise invisible until a build: a dataset regression, an SF
Symbol name that does not exist, a dangling reference in the Xcode project, a
table that would overflow the screen, a StoreKit product identifier that exists
in the configuration but not in the app, an element that resolves to no artwork
or no structure, and a color pairing that would miss WCAG AA.

Several of them exist because the mistake they catch cost a full macOS CI
cycle — forty-five minutes to be told one word. Each was added with the bug
still in the tree, so it is known to fire on the thing it is named for:

| Check | The error it replaces |
| --- | --- |
| `check_conformances.py` | `type 'X' does not conform to protocol 'Hashable'`, where the error names the outer type and not the property responsible |
| `check_undeclared.py` | `cannot find 'x' in scope` |
| `check_initializers.py` | an initializer call that no longer matches its type |
| `check_widget_shared.py` | a widget that builds and shows a placeholder forever |
| `check_table_fit.py` | a table that does not fit, which only a screenshot shows |
| `lint_sources.py` | `binary operator '+' cannot be applied to two 'OSLogMessage' operands`; `cannot use mutating member on immutable value: '$0' is immutable`; `Font.system` with its arguments transposed |

None of them is a compiler and none tries to be. Each answers one narrow
question that has a cheap, accurate answer without types, and skips whatever it
cannot read honestly rather than guessing.

**The live PubChem smoke suite** (`Tools/smoke_pubchem.py`) is deliberately not
in CI: it would make a green build depend on somebody else's uptime. Run it by
hand before a release and after any change to `PubChemClient`. It asks the real
service the questions the app asks — name lookup, formula search, auto-complete,
3D conformers, InChIKey and SMILES resolution — and checks the answers against
compounds whose identity will not change. It exits 2, distinctly from a
failure, when the network cannot be reached at all.

**UI tests** (XCUITest) cover launch, tapping an element into its detail page,
favoriting and seeing it appear in Study, searching by name, symbol and atomic
number, the empty search state, the four primary filters and the Families
card, Settings and its exact legal links, the practice tiles sharing one
baseline, a full
flashcard round through to its summary, answering a quiz question, an identify
round, the Progress screen, the redesigned Study layout, the free daily
allowance counting down (and not counting an abandoned round), the Pro badge,
the paywall opening and closing with its Restore and legal links, and the 3D
explorer opening for a free element while a gated one shows the paywall. Every query goes through an accessibility
identifier — no pixel coordinates.

---

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and push to `main`:

1. **validate-data** (Ubuntu) — every check in `Tools/verify.sh`, in seconds
2. **build-and-test** (macOS) — build for testing, unit tests, UI tests, then an
   unsigned Release build to catch optimiser-only failures
3. **smaller-and-larger-phones** (macOS, matrix) — launch and layout tests on a
   small iPhone, a Pro Max and an iPad, asserting the fitted table never overflows the
   screen width

Simulator destinations are resolved at run time by `Tools/pick_simulators.py`
from whatever the runner image actually has, rather than hard-coded by name —
GitHub rotates its device set, and a missing `iPhone 17 Pro` should not fail a
pipeline.

It never signs and never uploads.

---

## TestFlight

`.github/workflows/testflight.yml` archives, signs and uploads. It runs on a
`v*` tag or on demand.

By default it uses **Xcode cloud signing** driven by an App Store Connect API
key, so only four secrets are required:

| Secret | From |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect → Integrations → Team Keys |
| `APP_STORE_CONNECT_ISSUER_ID` | the same page |
| `APP_STORE_CONNECT_PRIVATE_KEY` | the downloaded `.p8`, contents verbatim |
| `APPLE_TEAM_ID` | developer.apple.com → Membership details |

Plus a repository **variable** `BUNDLE_IDENTIFIER` set to an identifier you own.

A manual-signing path exists for organizations that forbid cloud signing; it
activates automatically when `BUILD_CERTIFICATE_BASE64` is present.

Full walkthrough, including the App Store Connect setup and a troubleshooting
table: [`TESTFLIGHT.md`](TESTFLIGHT.md).

---

## Configuration

Everything you might want to change is in `Config/Shared.xcconfig`:

| Setting | Default | What it is |
| --- | --- | --- |
| `APP_DISPLAY_NAME` | `Elemora` | Name under the icon |
| `PRODUCT_BUNDLE_IDENTIFIER_BASE` | `com.idlery.periodicpro` | Registered at Apple. **Do not change** — see below |
| `MARKETING_VERSION` | `3.0.0` | Semantic version |
| `CURRENT_PROJECT_VERSION` | `1` | Build number; CI overrides it |
| `APP_DEVELOPMENT_TEAM` | *(empty)* | Your Team ID, via `Config/Local.xcconfig` or CI |
| `IPHONEOS_DEPLOYMENT_TARGET` | `18.0` | Minimum iOS version |

The team is left deliberately blank so a build can never quietly sign with the
wrong identity; CI supplies it from the `APPLE_TEAM_ID` secret.

### Names versus identifiers

Everything a customer reads says Elemora. Everything Apple matches on keeps its
original spelling, because none of it can be changed after the first upload.

| | Value | Kind |
| --- | --- | --- |
| App Store name | Elemora: Periodic Table | brand |
| Home Screen name | Elemora | brand |
| Paid tier | Elemora Pro | brand |
| Subscription group display name | Elemora Pro | brand |
| Product display names | Elemora Pro Monthly / Yearly | brand |
| Bundle identifier | `com.idlery.periodicpro` | **permanent identifier** |
| Monthly product identifier | `periodicpro.pro.monthly` | **permanent identifier** |
| Yearly product identifier | `periodicpro.pro.yearly` | **permanent identifier** |
| Subscription group identifier | `periodicpro.pro` | **permanent identifier** |
| Repository, `.xcodeproj`, scheme, target, test bundles | `PeriodicPro` | internal, wired into CI |
| GitHub repository variable | `BUNDLE_IDENTIFIER` = `com.idlery.periodicpro` | CI configuration |

`Tools/check_storekit.py` enforces both halves of this table: it fails if a
product identifier drifts, and it fails if a customer-facing name in
`Config/PeriodicPro.storekit` stops saying Elemora Pro.

---

## Screenshots

> Replace these with real device captures before submitting to the App Store.
> The launch UI test already attaches a full-screen capture of the table
> (`PeriodicProUITests/PeriodicProLaunchTests.swift`), which is a good starting
> point. App Store Connect needs 6.9" and 6.5" sets.

| Table | Element detail | Study | Progress |
| --- | --- | --- | --- |
| _screenshot pending_ | _screenshot pending_ | _screenshot pending_ | _screenshot pending_ |

In the meantime, `Design/` holds layout previews generated by
`Tools/preview_table.py`, `Tools/preview_detail.py` and `Tools/preview_study.py`.
They mirror the SwiftUI layout arithmetic rather than rendering the real app, so
they are useful for checking composition, legibility and density — not for the
App Store.

They earn their place by failing. `preview_study.py` asserts that the practice
tiles are still above the fold on the smallest supported phone, and rendering
the hero with its artwork composited in is how three separate mistakes were
found that reading the code had not: decoration sitting behind the tagline,
forms sliced by the canvas edge, and a mask whose stops erased most of what it
was meant to be shaping.

```bash
python3 -m pip install pillow
python3 Tools/preview_table.py          # the fitted table at three device widths
python3 Tools/preview_detail.py Au      # one element's detail page, unrolled
python3 Tools/preview_study.py          # the Study tab, light and dark
```

---

## Not in v1

Deliberately absent, and not accidentally missing: accounts, cloud sync, social
features, an AI tutor, ads, analytics, achievements, AR, and a settings screen.
The Compound Builder looks compositions up; it does not predict, simulate or
invent chemistry. The goal is one thing done properly — explore, understand,
memorize.

There is an optional subscription, Elemora Pro, and there is a 3D structure
explorer. Neither changes the rule above: no account is required for either,
nothing is measured about how you use them, and the periodic table itself is
free in full.

## Privacy

Nothing is collected. Everything you do stays on the device. Online compound
searches are sent to PubChem to retrieve requested chemical information, and
nothing else leaves. See [`PRIVACY.md`](PRIVACY.md).

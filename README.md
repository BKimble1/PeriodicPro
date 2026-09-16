# Elemora

A native iPhone app for exploring and memorizing the periodic table.

Listed on the App Store as **Elemora: Periodic Table**; **Elemora** under the
Home Screen icon; the optional paid tier is **Elemora Pro**.

The repository, the Xcode project, the scheme, the target and the bundle and
product identifiers are all still called `PeriodicPro` / `periodicpro`. That is
deliberate — Apple binds the App Store record and every subscriber receipt to
those strings, and they cannot be changed after an upload. See
[Names versus identifiers](#names-versus-identifiers).

All 118 elements, laid out correctly, in a table that fits the screen. Tap any
element and its tile expands into a full detail page. When you are ready to
remember rather than browse, three short practice modes turn what you read into
recall.

Built entirely in Swift and SwiftUI. No backend, no account, no network request,
no third-party dependencies. The whole thing works on a plane.

---

## Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Architecture](#architecture)
- [Folder structure](#folder-structure)
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
instantly — `oxygen`, `O` and `8` all land on the same element. Filter chips cut
the table to metals, nonmetals or metalloids; a compact filter sheet exposes all
ten families. A compact key beneath the table names every family and its glyph.

Two layouts: **fitted**, where every tile is on screen at once, and
**comfortable**, which scrolls horizontally with full-size tiles showing atomic
number, symbol and name. Accessibility text sizes switch to comfortable
automatically.

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

### Study

A greeting, two status cards that lead to Progress, one strong card into a
round, and four practice tiles:

- **Flashcards** — name → symbol and symbol → name, reveal, then rate yourself
- **Quiz** — four multiple-choice question types
- **Identify** — a glossy model of the atom, an atomic number, or a written clue
- **Smart Review** — ten cards drawn from the elements you keep getting wrong

Identify draws its model in neutral gray until you answer. The app teaches the
family palette during onboarding, so a lavender model would narrow 118
candidates to seven before you had counted a single shell.

Rounds start with the elements you know least well. Favorites and recently
studied elements sit lower on the same screen; an element you have favorited
appears only in Favorites, so the two rows never show the same tile twice.

Every number on the screen is read from the stored progress. A new learner sees
a 0-day streak and 0% mastered, not a demo value.

### Progress

Elements mastered out of 118 on a progress ring, a streak, cards answered, and a
per-family breakdown. No dashboard, no fake statistics — every number is derived
from something you actually did.

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
| Devices | iPhone, portrait and landscape |
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

Select the **PeriodicPro** scheme and any iPhone simulator, then ⌘R. It builds
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

PeriodicProTests/           Swift Testing unit tests
PeriodicProUITests/         XCUITest end-to-end flows
Config/                     xcconfig, Info.plist, StoreKit configuration
Tools/                      Dataset generation, validation and icon rendering
.github/workflows/          CI and TestFlight pipelines
```

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

**UI tests** (XCUITest) cover launch, tapping an element into its detail page,
favoriting and seeing it appear in Study, searching by name, symbol and atomic
number, the empty search state, family filters, the filter sheet, a full
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
   small iPhone and a Pro Max, asserting the fitted table never overflows the
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
| `MARKETING_VERSION` | `1.0.0` | Semantic version |
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
features, an AI tutor, ads, analytics, achievements, chemistry calculators, AR,
and a settings screen. The goal is one thing done properly — explore,
understand, memorize.

There is an optional subscription, Elemora Pro, and there is a 3D structure
explorer. Neither changes the rule above: no account is required for either,
nothing is measured about how you use them, and the periodic table itself is
free in full.

## Privacy

Nothing is collected. Everything you do stays on the device.
See [`PRIVACY.md`](PRIVACY.md).

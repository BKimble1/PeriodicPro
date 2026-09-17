#!/usr/bin/env python3
"""The branding gate: Elemora is what people read, PeriodicPro is what Apple matches.

The product has two name spaces and they are deliberately different, which is
exactly the situation where a well-meaning find-and-replace does real damage.
This script holds the line from both sides.

**No user-visible string may say "Periodic Pro".** Everything a customer reads
is Elemora or Elemora Pro. This is checked everywhere, including in comments and
documentation, because a stale name in a comment is how a stale name gets back
into the UI.

**Every retained `PeriodicPro` / `periodicpro` occurrence is named here.** Those
strings are not leftovers; they are the Xcode project, the scheme, the target,
the bundle identifier, the StoreKit product identifiers and the CI wiring, and
Apple binds permanent records to several of them. The allowlist below is the
documentation of which is which, and it is exhaustive: a new occurrence in a
file that is not listed fails, so the next person has to decide consciously
rather than by accident.

    python3 Tools/check_branding.py
"""
from __future__ import annotations

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The name the product used to have. Must not survive anywhere a person reads.
STALE_BRAND = "Periodic Pro"

# The brand, for the positive half of the check.
BRAND = "Elemora"

# Files that may still contain the stale brand, because they are what enforces
# its absence. Nothing else qualifies.
STALE_BRAND_ALLOWED = {
    "Tools/check_branding.py",
    "Tools/check_storekit.py",
}

# Files that must carry the brand, so that deleting it somewhere load-bearing is
# a failure rather than a silent regression.
BRAND_REQUIRED = {
    "Config/Shared.xcconfig": ["APP_DISPLAY_NAME = Elemora"],
    "Config/PeriodicPro.storekit": [
        '"name" : "Elemora Pro"',
        '"displayName" : "Elemora Pro Monthly"',
        '"displayName" : "Elemora Pro Yearly"',
    ],
    "PeriodicPro/Store/SubscriptionProduct.swift": [
        'subscriptionGroupDisplayName = "Elemora Pro"',
    ],
    "PeriodicPro/Store/PaywallView.swift": ['Text("Elemora Pro")'],
    "PeriodicPro/Store/ProBadge.swift": ['accessibilityLabel("Elemora Pro feature")'],
    "PeriodicPro/Views/Study/StudySession.swift": ['"Get Elemora Pro"'],
}

# Every place `PeriodicPro` or `periodicpro` is intentionally kept, and why.
#
# The key is a repository path; the value is the reason it is not a leftover.
# A path listed here may contain the identifier anywhere in the file. A path not
# listed here may not contain it at all.
RETAINED_IDENTIFIERS = {
    # --- Apple-permanent: changing any of these needs a new App Store record ---
    "Config/Shared.xcconfig":
        "bundle identifier com.idlery.periodicpro, registered at Apple",
    "Config/Local.xcconfig.sample":
        "sample override for the same bundle identifier",
    "Config/PeriodicPro.storekit":
        "StoreKit product identifiers periodicpro.pro.monthly and .yearly",
    "Config/Elemora.entitlements":
        "documents the signed app ID com.idlery.periodicpro the association file names",
    "PeriodicPro/Store/SubscriptionProduct.swift":
        "those product identifiers and the periodicpro.pro group identifier",
    "PeriodicProTests/ProGateTests.swift":
        "asserts the product identifiers have not drifted",

    # --- Xcode: project, scheme, target and test-bundle names ---
    "PeriodicPro.xcodeproj/project.pbxproj":
        "project, target and test-target names, and the source tree paths",
    "PeriodicPro.xcodeproj/xcshareddata/xcschemes/PeriodicPro.xcscheme":
        "the shared scheme CI builds by name",
    "PeriodicPro/App/PeriodicProApp.swift":
        "the @main App type and the com.periodicpro.app log subsystem",
    "PeriodicPro/App/AppEnvironment.swift":
        "names Config/PeriodicPro.storekit, the scheme's StoreKit configuration",
    "PeriodicProUITests/PeriodicProUITests.swift":
        "UI test class and target names",
    "PeriodicProUITests/PeriodicProLaunchTests.swift":
        "UI test class and target names",
    "PeriodicProUITests/ElemoraScreenshotTests.swift":
        "queries the paywall rows by their periodicpro.* product identifiers",

    # --- `@testable import PeriodicPro`: the module name is the target name ---
    "PeriodicProTests/ArtworkAndStructureTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/CatalogTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/ElementDataTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/FormattingTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/ProgressTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/SearchAndFilterTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/SmartReviewTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/StudyEngineTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/TableZoomTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/StructureProfileTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/TestSupport.swift": "@testable import PeriodicPro",
    "PeriodicProTests/CompoundTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/PubChemClientTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/QuizConfigurationTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/SavedQuizTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/Compound2DTests.swift": "@testable import PeriodicPro",
    "PeriodicProTests/SettingsTests.swift": "@testable import PeriodicPro",

    # --- Source naming the log subsystem or the test target ---
    "PeriodicPro/Store/SubscriptionManager.swift":
        "os.log subsystem com.periodicpro.app",
    "PeriodicPro/Persistence/PersistenceController.swift":
        "os.log subsystem com.periodicpro.app",
    "PeriodicPro/Data/ElementStructureCatalog.swift":
        "os.log subsystem com.periodicpro.app",
    "PeriodicPro/Compounds/Data/CompoundCatalog.swift":
        "os.log subsystem com.periodicpro.app",
    "PeriodicPro/Compounds/Data/CompoundCache.swift":
        "os.log subsystem com.periodicpro.app",
    "PeriodicPro/Compounds/Networking/PubChemClient.swift":
        "os.log subsystem com.periodicpro.app",
    "PeriodicPro/StudyEngine/SavedQuiz.swift":
        "os.log subsystem com.periodicpro.app",
    "PeriodicPro/Utilities/SFSymbolAllowlist.swift":
        "names the PeriodicProTests target in a doc comment",

    # --- CI: scheme, project, archive and artifact names ---
    ".github/workflows/ci.yml":
        "SCHEME and PROJECT, which must match the Xcode names",
    ".github/workflows/testflight.yml":
        "SCHEME, PROJECT, archive path and artifact name",

    # --- Tooling that reads or writes the project by path ---
    "Tools/backbone.py": "shared helper that resolves PeriodicPro source paths",
    "Tools/build_elements.py": "writes PeriodicPro/Data/elements.json",
    "Tools/check_contrast.py": "reads the PeriodicPro design system",
    "Tools/check_initializers.py": "walks the PeriodicPro source tree",
    "Tools/check_storekit.py": "reads Config/PeriodicPro.storekit and the scheme",
    "Tools/check_visual_routing.py": "walks the PeriodicPro source tree",
    "Tools/check_website.py": "reads PeriodicPro/Utilities/ElemoraLinks.swift and the app ID",
    "Tools/lint_sources.py": "walks the PeriodicPro source tree",
    "Tools/make_app_icon.py": "writes into PeriodicPro/Assets.xcassets",
    "Tools/normalize_spelling.py": "walks the PeriodicPro source tree",
    "Tools/preview_detail.py": "reads the PeriodicPro design system",
    "Tools/preview_table.py": "reads the PeriodicPro design system",
    "Tools/validate_elements.py": "reads PeriodicPro/Data/elements.json",
    "Tools/validate_project.py": "reads PeriodicPro.xcodeproj",
    "Tools/verify.sh": "runs the checkers over the PeriodicPro source tree",
    "Tools/check_branding.py": "this allowlist",
    "Tools/check_app_icon.py": "reads PeriodicPro/Assets.xcassets and the project",
    "Tools/check_swift_syntax.py": "walks the PeriodicPro source tree",
    "Tools/build_structures.py": "writes PeriodicPro/Data/structures.json",
    "Tools/validate_structures.py": "reads PeriodicPro/Data/structures.json",
    "Tools/build_compounds.py": "writes PeriodicPro/Data/compounds.json",
    "Tools/validate_compounds.py": "reads PeriodicPro/Data/compounds.json",
    "Tools/build_pubchem_fixtures.py": "writes PeriodicProTests/Fixtures",

    # --- The website, which has to name the signed app ID Apple matches ---
    "Website/site/.well-known/apple-app-site-association.template":
        "the app ID <TeamID>.com.idlery.periodicpro that iOS matches for Universal Links",
    "Website/scripts/build.sh":
        "prints the app ID shape it wrote, without the Team ID",
    "Website/README.md":
        "documents the app ID and the repository paths the site is kept in step with",

    # --- Documentation, which has to explain the split to a human ---
    "README.md": "documents which identifiers are retained and why",
    "TESTFLIGHT.md": "documents the bundle identifier and the scheme",
    "MONETIZATION.md": "documents the product identifiers",
    "APP_ICON.md": "asset-catalog path",
    "DATA_SOURCES.md": "path to PeriodicPro/Data/elements.json",
    "STRUCTURE_SOURCES.md": "paths to PeriodicPro/Data/structures.json and the test bundle",
    "COMPOUND_SOURCES.md": "paths to PeriodicPro/Data/compounds.json and the fixtures",
    "PRIVACY.md": "names the app bundle",
}

SEARCH_TERMS = ("PeriodicPro", "periodicpro")


def tracked_files() -> list[str]:
    output = subprocess.run(
        ["git", "-C", ROOT, "ls-files"],
        capture_output=True, text=True, check=True,
    ).stdout
    return [line for line in output.splitlines() if line]


def read(path: str) -> str | None:
    try:
        with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
            return handle.read()
    except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
        return None


def main() -> int:
    errors: list[str] = []
    files = tracked_files()

    contents = {path: read(path) for path in files}
    readable = {path: text for path, text in contents.items() if text is not None}

    # 1. The stale brand must be gone.
    for path, text in sorted(readable.items()):
        if path in STALE_BRAND_ALLOWED:
            continue
        if STALE_BRAND in text:
            lines = [
                f"{index}: {line.strip()}"
                for index, line in enumerate(text.splitlines(), 1)
                if STALE_BRAND in line
            ]
            errors.append(
                f"{path} still says {STALE_BRAND!r} — the product is {BRAND}:\n"
                + "\n".join(f"    {line}" for line in lines)
            )

    # 2. The brand must be present where it does work.
    for path, needles in sorted(BRAND_REQUIRED.items()):
        text = readable.get(path)
        if text is None:
            errors.append(f"{path} is missing, but the brand is asserted in it")
            continue
        for needle in needles:
            if needle not in text:
                errors.append(f"{path} no longer contains {needle!r}")

    # 3. Every retained technical identifier is accounted for.
    for path, text in sorted(readable.items()):
        if not any(term in text for term in SEARCH_TERMS):
            continue
        if path not in RETAINED_IDENTIFIERS:
            errors.append(
                f"{path} contains PeriodicPro/periodicpro but is not in "
                "RETAINED_IDENTIFIERS. If it is a technical identifier, add it "
                "there with the reason; if it is user-visible text, it should "
                f"say {BRAND} instead."
            )

    # A stale allowlist entry is its own kind of rot.
    for path in sorted(RETAINED_IDENTIFIERS):
        text = readable.get(path)
        if text is None:
            errors.append(
                f"RETAINED_IDENTIFIERS lists {path}, which is not a tracked text file"
            )
        elif not any(term in text for term in SEARCH_TERMS):
            errors.append(
                f"RETAINED_IDENTIFIERS lists {path}, which no longer contains "
                "PeriodicPro or periodicpro; remove the entry"
            )

    if errors:
        for error in errors:
            print(f"error: {error}")
        return 1

    print(
        f"OK — no user-visible {STALE_BRAND!r}; "
        f"{len(RETAINED_IDENTIFIERS)} files keep PeriodicPro/periodicpro on purpose, "
        "each with a documented reason"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

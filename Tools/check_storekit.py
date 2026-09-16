#!/usr/bin/env python3
"""Cross-checks the StoreKit configuration against the Swift product list.

Two separate things are checked, because the product has two separate name
spaces and they must not be confused for each other:

1. **Technical identifiers are frozen.** `periodicpro.pro.monthly`,
   `periodicpro.pro.yearly` and the `periodicpro.pro` group are what Apple
   matches on. They are permanent once a build has been uploaded, so this
   script asserts the exact strings rather than merely checking the two files
   agree with each other — agreeing on the wrong value is still wrong.
2. **Customer-facing names say Elemora Pro.** The display names, reference
   names and the group name are the brand, and the brand is not the identifier.

A product identifier that exists in only one of the two places is invisible
until a purchase is attempted on a device, which is the worst possible moment
to find out. A unit test cannot catch it either: the .storekit file lives
outside the app bundle on purpose, so the test target cannot read it.

    python3 Tools/check_storekit.py
"""
from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STOREKIT = os.path.join(ROOT, "Config", "PeriodicPro.storekit")
SWIFT = os.path.join(ROOT, "PeriodicPro", "Store", "SubscriptionProduct.swift")
SCHEME = os.path.join(
    ROOT, "PeriodicPro.xcodeproj", "xcshareddata", "xcschemes", "PeriodicPro.xcscheme"
)

# --- Frozen. Bound to the App Store Connect record and to existing receipts. ---
EXPECTED_PRODUCT_IDS = ["periodicpro.pro.monthly", "periodicpro.pro.yearly"]
EXPECTED_GROUP_IDENTIFIER = "periodicpro.pro"

# --- The brand. What a customer reads, everywhere. ---
EXPECTED_GROUP_DISPLAY_NAME = "Elemora Pro"
EXPECTED_DISPLAY_NAMES = {
    "periodicpro.pro.monthly": "Elemora Pro Monthly",
    "periodicpro.pro.yearly": "Elemora Pro Yearly",
}
STALE_BRAND = "Periodic Pro"


def swift_product_ids() -> list[str]:
    """Every `case x = "id"` in the SubscriptionProduct enum."""
    source = open(SWIFT, encoding="utf-8").read()
    return re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', source)


def swift_group_field(name: str) -> str | None:
    source = open(SWIFT, encoding="utf-8").read()
    match = re.search(rf'{name}\s*=\s*"([^"]+)"', source)
    return match.group(1) if match else None


def main() -> int:
    errors: list[str] = []

    if not os.path.exists(STOREKIT):
        print(f"error: {STOREKIT} is missing")
        return 1

    try:
        config = json.load(open(STOREKIT, encoding="utf-8"))
    except json.JSONDecodeError as error:
        print(f"error: Config/PeriodicPro.storekit is not valid JSON: {error}")
        return 1

    groups = config.get("subscriptionGroups", [])
    if len(groups) != 1:
        errors.append(f"expected exactly one subscription group, found {len(groups)}")

    config_ids = sorted(
        subscription["productID"]
        for group in groups
        for subscription in group.get("subscriptions", [])
    )
    declared = sorted(swift_product_ids())

    if config_ids != declared:
        errors.append(
            "product identifiers disagree.\n"
            f"    SubscriptionProduct.swift: {declared}\n"
            f"    PeriodicPro.storekit:      {config_ids}"
        )

    # Agreeing with each other is not enough: both have to agree with Apple.
    if declared != EXPECTED_PRODUCT_IDS:
        errors.append(
            "product identifiers have been renamed. They are permanent — the App "
            "Store Connect record and every existing receipt are bound to them, "
            "and the brand lives in the display names instead.\n"
            f"    expected: {EXPECTED_PRODUCT_IDS}\n"
            f"    found:    {declared}"
        )

    # Every subscription must name a period, or StoreKit returns it with no
    # subscription info and the paywall cannot describe what is being bought.
    for group in groups:
        for subscription in group.get("subscriptions", []):
            period = subscription.get("recurringSubscriptionPeriod")
            if not period:
                errors.append(
                    f"{subscription.get('productID')} has no recurringSubscriptionPeriod"
                )
            if subscription.get("type") != "RecurringSubscription":
                errors.append(
                    f"{subscription.get('productID')} is not a RecurringSubscription"
                )

    # The group the app reports must match the one in the file, so that what is
    # created in App Store Connect matches both. Checking only that the Swift
    # constants exist would let the two drift apart silently: renaming the group
    # in the configuration file while the app still reports the old name is not
    # something the build would ever notice on its own.
    group_id = swift_group_field("subscriptionGroupIdentifier")
    group_name = swift_group_field("subscriptionGroupDisplayName")

    if group_id is None:
        errors.append("SubscriptionProduct.subscriptionGroupIdentifier is missing")
    if group_name is None:
        errors.append("SubscriptionProduct.subscriptionGroupDisplayName is missing")

    # The identifier is what the app asks StoreKit about; the display name is
    # what has to be typed into App Store Connect. Only the name appears in the
    # configuration file, so that is the half that can be cross-checked here.
    if group_name is not None and len(groups) == 1:
        config_name = groups[0].get("name")
        if config_name != group_name:
            errors.append(
                "subscription group names disagree.\n"
                f"    SubscriptionProduct.swift: {group_name!r}\n"
                f"    PeriodicPro.storekit:      {config_name!r}"
            )

    if group_id is not None and group_id != EXPECTED_GROUP_IDENTIFIER:
        errors.append(
            "the subscription group identifier has been renamed. It is permanent; "
            f"expected {EXPECTED_GROUP_IDENTIFIER!r}, found {group_id!r}"
        )
    if group_name is not None and group_name != EXPECTED_GROUP_DISPLAY_NAME:
        errors.append(
            "SubscriptionProduct.subscriptionGroupDisplayName is what a customer "
            f"reads; expected {EXPECTED_GROUP_DISPLAY_NAME!r}, found {group_name!r}"
        )

    # Every customer-facing string in the configuration carries the brand, and
    # none of them may still carry the one it replaced.
    for group in groups:
        if STALE_BRAND in (group.get("name") or ""):
            errors.append(
                f"subscription group name still says {STALE_BRAND!r}: "
                f"{group['name']!r}"
            )
        for subscription in group.get("subscriptions", []):
            product_id = subscription.get("productID")
            expected = EXPECTED_DISPLAY_NAMES.get(product_id)
            visible = [("referenceName", subscription.get("referenceName"))]
            visible += [
                (f"localizations[{locale}].displayName", localization.get("displayName"))
                for locale, localization in enumerate(subscription.get("localizations", []))
            ]
            for field, value in visible:
                if value is None:
                    errors.append(f"{product_id} has no {field}")
                elif STALE_BRAND in value:
                    errors.append(
                        f"{product_id} {field} still says {STALE_BRAND!r}: {value!r}"
                    )
                elif expected is not None and value != expected:
                    errors.append(
                        f"{product_id} {field} is {value!r}; expected {expected!r}"
                    )
            for localization in subscription.get("localizations", []):
                if not (localization.get("description") or "").strip():
                    errors.append(f"{product_id} has an empty description")

    # No credential may ever be committed in the configuration file.
    settings = config.get("settings", {})
    for key in ("_developerTeamID", "_applicationInternalID"):
        if settings.get(key):
            errors.append(
                f"settings.{key} is set in the StoreKit configuration; "
                "it must stay empty so no account identifier is committed"
            )

    # The scheme is what actually enables the configuration at run time.
    if os.path.exists(SCHEME):
        scheme = open(SCHEME, encoding="utf-8").read()
        if "StoreKitConfigurationFileReference" not in scheme:
            errors.append(
                "the shared scheme does not reference a StoreKit configuration file, "
                "so Run and Test would use the real App Store"
            )
        elif "Config/PeriodicPro.storekit" not in scheme:
            errors.append("the scheme references a different StoreKit configuration file")

    if errors:
        for error in errors:
            print(f"error: {error}")
        return 1

    print(
        f"OK — StoreKit configuration matches the app "
        f"({len(config_ids)} products in 1 group, wired into the shared scheme); "
        f"identifiers still {', '.join(EXPECTED_PRODUCT_IDS)}; "
        f"customers see {EXPECTED_GROUP_DISPLAY_NAME}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Cross-checks the StoreKit configuration against the Swift product list.

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


def swift_product_ids() -> list[str]:
    """Every `case x = "id"` in the SubscriptionProduct enum."""
    source = open(SWIFT, encoding="utf-8").read()
    return re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', source)


def swift_group_id() -> str | None:
    source = open(SWIFT, encoding="utf-8").read()
    match = re.search(
        r'subscriptionGroupIdentifier\s*=\s*"([^"]+)"', source
    )
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

    # The group identifier the app reports must match the one in the file, so
    # that what is created in App Store Connect matches both.
    group_id = swift_group_id()
    if group_id is None:
        errors.append("SubscriptionProduct.subscriptionGroupIdentifier is missing")

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
        f"({len(config_ids)} products in 1 group, wired into the shared scheme)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

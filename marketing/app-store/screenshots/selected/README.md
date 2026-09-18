# Selected captures

The chosen, prepared capture for each device: the marketing status bar applied
(9:41, full signal, Wi-Fi, 100%) and any scroll indicator or stray row cleaned up.

Eight captures for six frames, because 03 and 05 each hold two devices. Name each
file with its frame number, and for the two-device frames include "front" or
"back" so the compositor can tell them apart:

    01-home.png            02-periodic-table.png
    03-front-build.png     03-back-compound.png
    04-element-detail.png
    05-front-study.png     05-back-quiz.png
    06-progress.png

Then, from marketing/app-store:

    python3 place_screenshot.py --all

Devices with no capture here are skipped and listed, so a half-finished set
still builds.

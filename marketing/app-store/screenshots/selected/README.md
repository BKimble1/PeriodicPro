# Selected captures

The chosen, prepared capture for each device: the marketing status bar applied
(9:41, full signal, Wi-Fi, 100%) and any scroll indicator or stray row cleaned up.

Seven captures for eight device slots, because the Build capture is used twice:
slides 2 and 3 are one composition and share it. Name each file with its frame
number, and where a frame holds more than one device include the role:

    01-home.png
    02-main-periodic-table.png      02-build-canvas.png
    03-build-canvas.png
    04-element-detail.png
    05-front-study.png              05-back-quiz.png
    06-progress.png

The three Build entries are the same file under three names; copy it.

Then, from marketing/app-store:

    python3 place_screenshot.py --all

Devices with no capture here are skipped and listed, so a half-finished set
still builds.

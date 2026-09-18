# Selected captures

The chosen, prepared capture for each frame: the marketing status bar applied
(9:41, full signal, Wi-Fi, 100%) and any scroll indicator or stray row cleaned up.

Name each file with its frame number so the compositor can find it:

    01-home.png  02-periodic-table.png  03-build.png  04-element-detail.png
    05-study.png  06-progress.png  07-favorites.png  08-overview.png

Then, from marketing/app-store:

    python3 place_screenshot.py --all

Frames with no capture here are skipped and listed, so a half-finished set still
builds.

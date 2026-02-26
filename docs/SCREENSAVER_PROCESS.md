# Screensaver Process (Projector Local Idle Image)

## Purpose
Establish a reliable fallback/idle image on Epson LS800 projectors by rendering a local file on the projector itself via ADB.

This avoids flaky network playback contexts and gives a stable "turn-on" visual when media flow is degraded.

## Current Status
- Verified working on **Projector A** (`192.168.0.11`)
- To be applied to **Projector B** (`192.168.0.12`) once ADB authorization is restored

## Source Asset
- Home Assistant media source file:
  - `/opt/homeassistant/www/Projector A 4k.jpg`

## One-Time Setup (A)
From control host (`piserver.local`):

```bash
# 1) Pull image from HA local endpoint to control host temp
curl -sS -L 'http://192.168.0.10:8123/local/Projector%20A%204k.jpg' -o /tmp/ProjectorA4k.jpg

# 2) Connect ADB
adb connect 192.168.0.11:5555

# 3) Push image to projector local storage
adb -s 192.168.0.11:5555 push /tmp/ProjectorA4k.jpg /sdcard/Download/ProjectorA4k.jpg

# 4) Open local file in Gallery
adb -s 192.168.0.11:5555 shell am start -W \
  -a android.intent.action.VIEW \
  -d 'file:///sdcard/Download/ProjectorA4k.jpg' \
  -t 'image/jpeg'
```

## Expected Result
- Gallery opens with local image
- On reboot/power cycle, projector often auto-resumes to same image context

## Recovery Command (A)
```bash
adb -s 192.168.0.11:5555 shell am start -W \
  -a android.intent.action.VIEW \
  -d 'file:///sdcard/Download/ProjectorA4k.jpg' \
  -t 'image/jpeg'
```

## Planned for B
When B is re-authorized in ADB:

```bash
adb connect 192.168.0.12:5555
adb -s 192.168.0.12:5555 push /tmp/ProjectorA4k.jpg /sdcard/Download/ProjectorA4k.jpg
adb -s 192.168.0.12:5555 shell am start -W \
  -a android.intent.action.VIEW \
  -d 'file:///sdcard/Download/ProjectorA4k.jpg' \
  -t 'image/jpeg'
```

## HA Integration Target
Create a script (`show_idle_image_a`) and call it when:
- projector turns on
- playback fails
- guard ends and system returns to idle

This document defines the baseline procedure for that automation.

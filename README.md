<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="SpotiText icon">
</p>

<h1 align="center">SpotiText</h1>

A floating lyrics overlay for macOS that shows synced lyrics for whatever is playing in Spotify — made for singing along.

## Features

- Synced lyrics from [LRCLIB](https://lrclib.net), with word-by-word highlighting when word timings are available
- Smooth scrolling overlay that stays on top of all windows, spaces and full-screen apps
- Playback controls, seek bar and lyrics offset right on the widget
- Choose between different lyrics versions for a track (your choice is remembered)
- Romanization for Japanese, Korean, Chinese and other non-Latin scripts
- Ukrainian translation using Apple's on-device Translation framework
- Countdown dots before lyrics start after long instrumental parts
- Customizable background color, opacity, blur and font size
- Click-through lock mode
- Resizable down to a single line — text scales with the window

## Requirements

- macOS 26 or later
- Spotify desktop app

## Install

Download `SpotiText.dmg` from [Releases](../../releases), open it and drag **SpotiText** to **Applications**.

The app is not notarized, so on first launch right-click it and choose **Open**.
When asked, allow SpotiText to control Spotify — it needs this to read the current track and playback position.

## Build from source

```sh
./build.sh
```

This builds `SpotiText.app` and packages `dist/SpotiText.dmg` and `dist/SpotiText.zip`.
Requires Xcode or the Command Line Tools with the macOS 26 SDK.

## Translation languages

Translation runs fully on-device. If a language pack is missing, SpotiText offers to download it,
or you can add languages in **System Settings → General → Language & Region → Translation Languages**.

## License

[GPL-3.0](LICENSE)

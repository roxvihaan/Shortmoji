# Shortmoji

**Discord-style emoji shortcodes, across your Mac.**

Shortmoji is a small native macOS menu-bar utility that turns `:skull:` into 💀 while you type. A compact suggestion panel appears near your cursor, helping you find emoji by name, alias, or related meaning without leaving your text field.

![Shortmoji playground showing live emoji shortcode suggestions](screenshots/shortmoji-playground.png)

## Features

- Type a prefix such as `:sku` to open related emoji suggestions.
- Use Up/Down to select and Return or Tab to insert.
- Type a complete shortcode such as `:skull:` to replace it immediately with 💀.
- Search uses names, aliases, related keywords, and light fuzzy matching.
- Click **See similar** to browse related emoji in a compact grid, then type to search the bundled catalog.
- Navigate the grid with arrow keys; press Return or Tab to insert. Backspace edits the search, and Escape clears it or returns to suggestions.
- Native AppKit materials, system emoji, and a quiet menu-bar presence.
- Text stays local; the app has no network code.

Shortmoji needs macOS Accessibility access to observe global typing and insert the selected emoji. The packaged app uses a stable local designated requirement so this permission survives rebuilds.

## Download and install

Download the DMG from [Releases](https://github.com/roxvihaan/Shortmoji/releases), open it, and drag **Shortmoji.app** onto **Applications**. Launch Shortmoji and follow the Accessibility prompt. Its menu-bar menu also includes a playground for trying shortcodes.

**Requirements:** Apple Silicon Mac, macOS 14 Sonoma or later.

This initial release is locally signed and **not notarized by Apple**. macOS may block the first launch. If you trust the download, review the blocked-app notice in System Settings → Privacy & Security and choose Open Anyway.

## Privacy and limitations

Shortmoji observes keyboard input locally to recognize shortcodes and uses Accessibility plus clipboard-based insertion to replace text. It does not send typed text to a server. Support depends on the target app; secure fields and apps that intercept keyboard input may not work. The bundled catalog contains 1,867 emoji, including ninja, melting face, saluting face, flags, and professions. It incorporates [GitHub’s gemoji data](https://github.com/github/gemoji) with Shortmoji’s existing aliases and search keywords. New Unicode additions and skin-tone combinations are not all included; glyph support also depends on your macOS version. The upstream license is bundled with the app.

## Development

Requires Xcode with the macOS SDK and Node.js. No npm dependencies are needed.

```sh
npm test        # Search, shortcode state, and native interaction regression tests
npm run build  # Build and sign release/Shortmoji.app
npm run dmg    # Build a versioned drag-to-install DMG
```

The DMG script refuses to overwrite an existing versioned installer. Release binaries belong in GitHub Releases, not the source repository.

Built with Swift and AppKit using Swift Package Manager. Source is in `Sources/`, regression tests in `Tests/`, and packaging scripts in `scripts/`.

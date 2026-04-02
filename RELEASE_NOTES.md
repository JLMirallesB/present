# Present 1.0 - Enhanced Fork

## What's New

This is an enhanced fork of [simonw/present](https://github.com/simonw/present) with professional presentation management features.

### New Features

✨ **Display Names for Slides**
- Add custom names to each slide for better organization
- Display names are shown in the sidebar instead of full URLs
- Easily identify slides at a glance

✨ **Multiple Presentation Lists**
- Save and manage multiple presentations within the app
- Switch between presentations with a simple dropdown selector
- Each presentation list maintains its own set of slides
- Automatically remembers the last presentation you were working on

✨ **Safe Editing Modal**
- Edit slide information in a dedicated modal dialog
- Prevents accidental changes from clicks
- Edit both the display name and URL in one place

✨ **Improved Keyboard Navigation**
- Use **Cmd+↑** to go to the previous slide
- Use **Cmd+↓** to go to the next slide
- Original arrow keys still work for web page navigation
- No more conflicts with form inputs in web pages

✨ **Better Organization**
- Toolbar with presentation list selector
- Buttons to create, rename, and delete presentation lists
- Confirmation dialogs to prevent accidental deletions

## Installation

1. Download `Present-1.0.dmg` from the releases
2. Open the DMG file
3. Drag `Present.app` to your Applications folder
4. Launch from Applications folder or Spotlight (Cmd+Space)

## Usage

### Creating a New Presentation List
1. Click the "+" button in the sidebar
2. Enter a name for your presentation list
3. Start adding slides with URLs

### Adding a Slide
1. Click the "+" button at the bottom of the sidebar
2. A new slide appears with a default URL
3. Click the pencil icon to edit the display name and URL

### Editing Slides
1. Click the pencil icon next to a slide
2. Edit the display name (optional) and URL (required)
3. Click "Save" to confirm changes

### Presentation Mode
1. Click **Presentation > Play** (Cmd+Shift+P)
2. Navigate with Left/Right arrows or Cmd+Up/Cmd+Down
3. Press Escape to exit

## Requirements

- macOS 14.0 or later
- Apple Silicon or Intel Mac

## Technical Details

### Architecture Improvements
- Slides now support display names via optional property
- Complete refactor to support multiple presentation sets
- JSON-based persistence for robust data management
- Automatic migration from previous version format

### Data Migration
- Existing presentations are automatically converted to the new format
- Old presentation files (plain text) are still supported
- The first imported presentation becomes the "Default" list

## Known Limitations

- The app is not signed or notarized, so you may see security warnings on first launch
  - Right-click the app and select "Open" to bypass this
- Remote control server (port 9123) functionality inherited from original
- No iCloud sync (presentations stored locally)

## Credits

- Original app: [Simon Willison](https://github.com/simonw/present)
- Enhancements: Added display names, multiple presentation lists, and improved UX

## License

Apache License 2.0 (same as original)

---

**Note**: This is a fork created with improvements for better presentation management. For the original app, visit [simonw/present](https://github.com/simonw/present).

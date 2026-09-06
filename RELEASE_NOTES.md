# Present 2.0 — Enhanced Fork

Everything since 1.0 (April 2026). The 1.0 build was the fork's first pass:
display names, multiple lists and a modal editor on top of
[simonw/present](https://github.com/simonw/present). This release is about
making it hold up in front of an audience — and making it safe to keep.

## New

✨ **Text slides, written in Markdown**
- Not every slide needs a web page: a title, a section break, a closing slide
- Written in Markdown and rendered by the app itself
- Slide text is HTML-escaped, so `<`, `>` and `&` show as written

✨ **Presenting with a real remote**
- Page Up / Page Down, which is what presentation clickers send — a physical
  remote did nothing at all before
- `B` blanks the screen mid-talk, Home / End jump to the ends
- ↑, ↓ and space stay with the page, so a slide that is a long article scrolls
- The next and previous slides preload while you talk: no white rectangle
  filling in, and a slide you return to keeps its scroll position
- With more than one display connected, **Presentation > Display** picks one

✨ **The phone remote now needs a key**
- Every endpoint requires a token, generated per launch and never persisted
- **Presentation > Remote Control** (Cmd+Shift+R) shows it as a QR code, and
  can turn the server off entirely
- Without it, any page open in any browser on your Mac could advance your
  slides with a single `fetch()`, and so could anyone on the same network

✨ **Lossless Save, and a real Save vs Save As**
- Cmd+S writes back to the file the list came from; Save As moves to Cmd+Shift+S
- Two formats, both lossless: `.json` is native and carries the list name;
  `.txt` stays one slide per line and interchangeable with upstream and with
  [kcarnold's fork](https://github.com/kcarnold/present)
- Opening sniffs the content rather than trusting the extension
- Save failures surface as an alert instead of being swallowed

✨ **The file is watched**
- Edit the list in an editor while the app holds it and the list reloads itself
- With unsaved edits, nothing is touched and the title says so
- A change arriving mid-presentation waits until the talk is over
- Save refuses to bury a change it did not make, and offers to reload instead

✨ **Copy links out**
- A button per row: on a URL slide, its name and address
- On a text slide, the whole section it heads — its markdown and every link
  below it, down to the next text slide

## Fixed

- **Lists were not actually being remembered.** `currentSetId` was never
  persisted, and creating a list saved the *previous* one. Lists and the
  selected list are now one document written atomically to Application Support
- **Typing `=` or `-` into a web page changed the zoom** during a presentation
- **A data race in the remote server** between the network queue and the model
- **Editing a slide never marked the list as changed**, because `Slide` is a
  reference type and the array's `didSet` never fired

## Under the hood

- 106 model tests — persistence and its migrations, navigation, reordering, the
  file formats, reloading, link copying, the Markdown renderer, the keymap and
  the remote's access checks — running in about two tenths of a second
- GitHub Actions runs them, builds Release and uploads the app on every push
- Swift 6 with strict concurrency
- Bundle identifier is now `es.jlmirall.present`

## Installation

1. Download `Present-2.0.dmg` below
2. Open it and drag `Present.app` to your Applications folder
3. **First launch: right-click the app and choose "Open"** — the app is not
   signed or notarized, so double-clicking is refused

## Requirements

- macOS 14.0 or later
- Apple Silicon or Intel Mac

## Known limitations

- Not signed or notarized (see installation above)
- Web slides need a network connection; text slides are what survives without one
- The file association lasts for the session: under the sandbox, permission to
  write a file you picked does not outlive the launch that granted it, so after
  relaunching, Save asks again where to put it
- Anyone you hand the remote address to can drive the presentation. Treat it as
  you would the clicker itself
- No iCloud sync — lists are stored locally

## Credits

- Original app: [Simon Willison](https://github.com/simonw/present)
- Text slide idea (not the implementation): [kcarnold's fork](https://github.com/kcarnold/present)

## License

Apache License 2.0 (same as original)

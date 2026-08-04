<div align="center">

<img src="docs/images/icon.png" width="128" alt="Stash">

# Stash

**Clipboard history for macOS that you can actually see.**

Press ⌥⌘V and your history slides up from the bottom of the screen as a strip
of cards. Pick one, press ↵, and it lands in whatever you were typing in.

</div>

<img src="docs/images/strip.png" alt="The Stash strip: cards for an image, a note, a link, a masked token, a pinned command, a colour, and a file">

## Why another clipboard manager

macOS has no built-in clipboard history. The free managers are list-based and
show images badly; the ones with a card interface are paid. Stash is the card
interface, free, and local-only.

But the reason to use it is in the details below — the behaviour a clipboard
manager only gets right if someone bothered.

## The details that took the work

**Pasting an image adapts to where it lands.** Paste into Notes and you get the
image. Paste into Terminal — which cannot accept images at all — and you get
the file's path instead of nothing. Paste into Finder and you get the file.
Each destination takes the richest thing it understands, the way macOS itself
behaves when you copy a file.

**It never records what your password manager copies.** Apps signal "don't
store this" with an unofficial but widely honoured pasteboard type
(`org.nspasteboard.ConcealedType` and friends). Stash checks that *before*
reading any content. 1Password and Keychain Access are blocklisted on top of
that, and you can add more.

**Masking knows a link from a token.** A bare URL stays readable — hiding every
GitHub link you copy would make the strip useless. But if a link's path or
query carries a credential (a password reset, a magic link, a presigned S3
URL), that gets masked. Card numbers are checked with a Luhn checksum, so an
ISBN or a tracking number is not mistaken for a card.

**It doesn't re-capture its own paste.** Without that, every paste would
overwrite the card's "copied from" with wherever you pasted it, and a filtered
paste would silently duplicate the entry.

**When it can't paste, it says so.** No Accessibility permission, or the
keystroke couldn't be posted — either way you get told the content is on the
clipboard and ⌘V is yours. It never closes the strip having done nothing.

**It can watch your screenshot folder.** ⌘⇧4 writes a file and never touches
the clipboard, so no clipboard manager can see it. Turn this on and Stash picks
up new screenshots from wherever macOS saves them. Off by default; only files
macOS itself tags as screenshots; only ones created after you turned it on.

**A corrupt database is moved aside, never deleted.** We can't recover it — but
it's yours, and throwing it away isn't ours to do. Stash opens a fresh one,
keeps the old file next to it, and tells you where it went. Integrity is
checked at open with `PRAGMA quick_check`, so a half-written page is caught
then rather than surfacing as a mystery failure later.

**Deleting a shelf keeps its cards.** You're removing a folder, not binning
what was in it.

**"Clear everything" spares what you pinned** — and actually deletes the image
files, not just the rows.

**The sounds don't lie.** Silent for the clipboard content that's already there
at launch. Silent for anything deliberately not stored. And if a paste degrades
to a copy, you hear the copy sound, not the paste one.

**Card controls act on the card under the pointer**, not the selected one — so
reaching for the mouse never changes what ↵ would paste.

## Install

No Homebrew formula and no signed release; build it from source.

```bash
git clone https://github.com/selinihtyr/stash-clipboard.git
cd stash-clipboard
./scripts/bundle.sh
cp -R build/Stash.app /Applications/
open /Applications/Stash.app
```

macOS may block an unsigned app on first launch: right-click Stash in
`/Applications` and choose **Open**.

### Signing — read this, or pasting will look broken

The Accessibility permission is bound to the app's signature, so how it is
signed directly affects daily use. `scripts/bundle.sh` picks, in order:

1. `STASH_SIGN_IDENTITY` if you set it,
2. otherwise the first developer certificate on the machine (Apple Development
   or Developer ID),
3. otherwise an ad-hoc signature.

**Signed with a certificate**, the identity is stable and the permission
survives rebuilds — grant it once and you're done.

**Signed ad-hoc**, there is no stable identity to bind to, so macOS ties the
permission to the signature's hash, which changes every time the binary does.
**Every rebuild silently invalidates the permission**: Stash keeps working, but
paste quietly degrades to copy. Remove and re-add Stash under System Settings →
Privacy & Security → Accessibility, or run
`tccutil reset Accessibility social.selin.stash` and grant it again.

## Permissions

**Accessibility** is required for direct pasting (System Settings → Privacy &
Security → Accessibility). Without it Stash still works — it copies your
selection and leaves ⌘V to you.

The global shortcut needs no permission at all (it uses Carbon's
`RegisterEventHotKey`, not an accessibility observer).

**Files and Folders** is required only if you enable screenshot-folder
watching. Refuse it and the switch turns itself back off and tells you why — it
never sits there looking "on" while doing nothing.

## Shortcuts

| Key | Action |
|---|---|
| ⌥⌘V | Open/close the strip |
| ← → | Move between cards |
| typing | Search history |
| ⌫ | Edit the search text |
| ↵ | Paste |
| ⌥↵ | Paste with filters applied |
| ⌘1…⌘9 | Paste the card at that position |
| ⌃P | Pin / unpin |
| ⌃S | Move to shelf |
| ⌘⌫ | Delete the card |
| ⇥ | Switch tab |
| Esc | Close |

⌫ edits the search box rather than deleting a card — deleting moved to ⌘⌫ so
you can't lose a card while typing a search.

## Privacy

- **By default it watches only the clipboard.** Screenshot-folder watching is
  the single feature that reaches beyond it, and it is opt-in and off by
  default.
- **No network code.** Stash connects to nothing. You can verify it:
  `grep -rn "URLSession\|import Network\|CFSocket\|NWConnection" Sources`
  returns nothing.
- **Password-manager content is never stored** — see above.
- **Card numbers and tokens are masked** on the card face, revealed with a
  double-click.
- **The database is not encrypted.** `~/Library/Application Support/Stash/` is
  readable only by your user (mode `0700`), but encryption at rest is
  FileVault's job. With FileVault off, your history sits there in plain text.

### Known limits of masking

- Text containing a space is never masked, so a `Bearer eyJ…` header, a
  `curl -H "Authorization: …"` line, or a sentence like "my password is …"
  shows in full.
- This is a shoulder-surfing deterrent, not a data-loss-prevention boundary.
  It's heuristic: occasionally it hides something ordinary (double-click to
  reveal) and occasionally it misses something unusual.

## Launch at login

The "Launch at login" switch uses `SMAppService.mainApp`, which requires Stash
to be installed as a proper bundle in `/Applications` — registration fails for
a copy run straight out of the build directory. If registration fails the
switch reflects reality rather than what you clicked, and says why.

## Development

```bash
swift test                  # all modules
./scripts/bundle.sh debug
```

Architecture and the reasoning behind each decision:
`docs/superpowers/specs/2026-08-04-stash-clipboard-design.md`

Manual QA checklist to run before a release: `docs/manual-qa.md`

## Sound credits

The copy and paste sounds (`Sources/Stash/Resources/Sounds/`) are not macOS
system sounds. They are two separate Freesound recordings under two different
licences, and **neither is covered by this project's MIT licence**.

**`copy.wav` — attribution required**

- Source: "soft sound plastic button click" by orginaljun —
  https://freesound.org/s/150382/
- Licence: Creative Commons Attribution 3.0 Unported (CC-BY 3.0) —
  https://creativecommons.org/licenses/by/3.0/
- Changes: downmixed to mono, trimmed, tail faded, level lowered. CC-BY 3.0
  permits derivatives and requires changes to be marked; this line marks them.

**`paste.wav` — no attribution required**

- Source: "inventory_select" by obrymec — https://freesound.org/s/580829/
- Licence: Creative Commons 0 (CC0) —
  https://creativecommons.org/publicdomain/zero/1.0/
- Changes: downmixed to mono, trimmed, tail faded, level adjusted. The credit
  above is a courtesy.

The same terms sit next to the files in
`Sources/Stash/Resources/Sounds/CREDITS.txt`, so they travel with the folder if
it is copied out of the repo.

## Licence

Code: MIT. The two sound files are excluded — `copy.wav` is CC-BY 3.0 and
`paste.wav` is CC0 (see Sound credits).

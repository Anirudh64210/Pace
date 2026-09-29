# Security

Pace runs entirely on your Mac. It has no server, no analytics and no account system, and it never reads your conversations. This page lists every place Pace touches your data, so you can check it yourself.

## Data sources

### Claude Code status line (default)

Claude Code passes its rate limit numbers to a status line script. Pace's script, `scripts/pace-statusline.sh`, saves them to `~/Library/Application Support/Pace/status.json`, and the app reads that file.

- The file holds only percentages, reset times and a save time. Session ids, paths, model names and prompt text are dropped before anything is written.
- The folder and file are created readable by you only.
- Input is parsed as data and never executed. Values out of range, such as a reset time more than eight days away, are dropped. The test suite feeds the script malformed, binary, oversized, out-of-range and shell-injection input.
- Several Claude Code sessions can run the script at once. Writes happen under a file lock through a unique temporary file, so the file is never half written and a stale session cannot overwrite newer numbers.
- The script needs `/usr/bin/python3`, which comes with the Xcode Command Line Tools. Without them it prints a one-line hint instead of opening an installer dialog.
- No credentials are involved.

**Your previous status line.** If you had a status line before installing, its command is saved to `~/.claude/pace-statusline-chain`, and **the script runs that command** on every status line update, exactly as Claude Code used to. It is only run if the file is owned by you and not writable by anyone else. It runs with your original umask. Treat this file like `settings.json`: anything that can write it can run code as you. **Settings › Remove** deletes it and puts the original entry back in `settings.json`.

### Claude sign-in (optional)

When this source is selected, Pace uses the OAuth token that Claude Code stores in your login Keychain, in the item named `Claude Code-credentials`. The Claude desktop app's built-in Claude Code sometimes can only save a renewed sign-in to `~/.claude/.credentials.json` ([anthropics/claude-code#94464](https://github.com/anthropics/claude-code/issues/94464)), so Pace also reads that file, only if it is a regular file owned by you and readable by no one else, and uses whichever copy expires last. `make check` (`Pace --check`) also reads it once, to test the source, whichever source is selected.

- **Reading.** Pace runs Apple's `/usr/bin/security find-generic-password -w`, the tool Claude Code uses to store the item. The item normally trusts that tool, so there is no password prompt, and Pace never changes the item's access list. If your keychain is locked, or the item's access list is different, macOS may ask for your password. If nobody answers within 15 seconds, Pace stops the tool, says so, and waits for you to retry. The command runs with a minimal environment and no input. The token comes back through a pipe and never appears on a command line.
- **In memory only.** Pace reads the token once and keeps it in memory until it expires. If Anthropic rejects it, Pace reads it once more, because Claude Code may have renewed it. If the sign-in has expired, Pace re-reads the two local copies once a minute, without any network request, until Claude Code has renewed it.
- **Never renewed or written by Pace.** Anthropic's renewal credentials are single use and rotate. A second program renewing them would invalidate the copy Claude Code holds and could sign you out, so Pace only ever reads. For the same reason it never runs `claude auth status` or other short-lived Claude Code commands, which can spend the renewal credential without saving the result ([anthropics/claude-code#95822](https://github.com/anthropics/claude-code/issues/95822)).
- **Never on disk.** The token is never written to a file, to UserDefaults or to a log. Printing, dumping or reflecting the credentials shows `<redacted>`.
- **One destination.** It is sent only as a bearer token to `https://api.anthropic.com/api/oauth/usage`. The host and scheme are pinned in code.
- **No HTTP storage.** Requests use an ephemeral session with no cache, cookies or credential storage. Redirects are refused, so the Authorization header cannot follow one to another host; a test performs a real redirect to prove it. At launch Pace turns off Foundation's shared HTTP cache, and deletes any cache database an older build left behind, because macOS archives request headers inside it.
- **Errors never echo responses.** Error text shown in the app never includes response bodies or the token.
- **Proxies.** Requests use your system proxy settings, over TLS. A proxy only sees the token if you have installed a root certificate that lets it intercept HTTPS, as some corporate networks do.
- **How Pace identifies itself.** Because it uses Claude Code's sign-in, Pace sends a Claude Code user agent that also names Pace and links to this repository.

That token is a full account credential, not a read-only key. Only enable this source if you are comfortable with that. The endpoint and the Keychain item are not documented by Anthropic, so treat this source as best effort, and check Anthropic's terms before relying on it.

## Files Pace writes

| Path | Contents |
|---|---|
| `~/Library/Application Support/Pace/status.json`, `status.lock` | Percentages and reset times from the status line. Readable by you only |
| `~/Library/Application Support/Pace/token-cache.json` | For the "about N tokens" figure: the path of each Claude Code transcript, a byte offset and a token count. Paths include your username and project folder names. Readable by you only |
| `~/Library/Preferences/org.pace-menubar.Pace.plist` (`Pace.plist` under `swift run`) | Your settings, the apple count, and which resets you were already notified about |
| `~/.claude/pace-statusline.sh` | The status line script |
| `~/.claude/pace-statusline-chain`, `pace-statusline-previous.json` | Your previous status line, if you had one. Readable by you only |
| `~/.claude/settings.json.pace-backup` | A copy of `settings.json` from before the install. Readable by you only. It can include anything in your settings, such as `env` values |

**Settings › Remove** deletes the script, the chain files, the backup and `status.json`, and restores your previous status line exactly.

For the token count, Pace scans Claude Code's transcripts under `~/.claude/projects` for the numeric `input_tokens` and `output_tokens` fields only, in 4 MB chunks, skipping anything that is not a regular file. It never stores or displays any text from them.

## System integration

- **Start at login** uses macOS's own login item service (`SMAppService`). It is listed, and can be turned off, in System Settings › General › Login Items.
- **The status pill** is a small window of Pace's own that ignores the mouse. It needs no permission.
- **The shortcut** (⌃⌥P by default, or any you record) uses the Carbon hot key API. It needs no Accessibility or Input Monitoring permission, and macOS delivers only that one key combination to Pace. Pace never sees anything else you type.

## How the installer edits `settings.json`

- It never writes a file it cannot read or parse, and a symlink pointing at a missing file is an error, not an empty file.
- It follows a symlinked `settings.json` and writes the file it points to, so dotfile managers keep working.
- The new file is created with the old file's permissions from the start, then renamed into place. Hard links, extended attributes and ACLs on the old file are not carried over.
- If Claude Code changes the file while Pace is writing, Pace stops without changing anything.
- The JSON is rewritten with sorted keys and standard formatting. Your values are kept. Number formatting can change slightly, for example `1.0` becomes `1`.
- It honours `CLAUDE_CONFIG_DIR` when Pace is started with it set.

## Verify it yourself

```sh
grep -rn "https://" Sources            # every URL: the usage endpoint and the usage settings page
grep -rn "Process()" Sources           # every external command: only the Keychain read
swift test                             # token safety, redirect, installer, script and fuzz tests
make check                             # runs both sources once, prints percentages only
```

The relevant code is short:

- `Sources/Pace/Providers/Keychain.swift` reads the token.
- `Sources/Pace/Providers/OAuthUsageProvider.swift` makes the one request.
- `Sources/Pace/System/Hygiene.swift` handles launch cleanup.
- `Sources/Pace/System/StatusLineInstaller.swift` edits Claude Code's settings.
- `scripts/pace-statusline.sh` is the status line script.

## Reporting a problem

Please report security issues privately through GitHub's **Report a vulnerability** button on the repo's Security tab, not as a public issue. Never paste a token into an issue.

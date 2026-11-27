# Rubber Stamp

A macOS menu bar app for GitHub pull requests where you are requested as a reviewer.
It has two modes:

- **Manual**: lists the PRs waiting for your review, each with an *Approve* button.
- **Auto-approve**: approves them on every check, optionally only in certain repos or from
  certain authors. Drafts are never auto-approved.

The menu bar icon shows how many review requests are open.

> Auto-approving skips the review. Use the repo and author rules to keep it to PRs you
> would approve without looking anyway.

## Install

Requires macOS 13 or later, the Xcode Command Line Tools (`xcode-select --install`) and
the [GitHub CLI](https://cli.github.com), logged in with `gh auth login`.

```sh
brew tap gianhiltbrunner/rubber-stamp https://github.com/gianhiltbrunner/rubber-stamp
brew install rubber-stamp
rubber-stamp                     # starts the app
```

Homebrew builds the app from source on your machine, so macOS does not block it as an
unsigned download. To have it in Launchpad and Spotlight:

```sh
ln -sf "$(brew --prefix)/opt/rubber-stamp/Rubber Stamp.app" /Applications/
```

Update with `brew upgrade rubber-stamp`.

## How it works

- **Authentication**: the app has no login of its own. It runs the `gh` CLI and uses the
  account `gh` is logged in with. Every approval is made as that account. The app stores
  no token.
- **Which PRs**: open, non-archived PRs found with the search
  `user-review-requested:@me`. Requests to one of your teams are not included.
- **Checks**: every 1 to 30 minutes, set in Settings (gear icon), plus the refresh button.
- **Auto-approve rules** (Settings), comma-separated, not case-sensitive:
  - Repos: `owner/repo` or `owner/*` allows, `!owner/repo` excludes.
  - Authors: GitHub logins, for example `alice, my-app[bot]`; `!login` excludes.
  - An empty field allows everything. A PR must pass both fields.
- **If an approval fails** (for example on your own PR), the error is shown and that PR is
  not retried automatically.
- **Settings** are stored in the app's macOS preferences
  (`defaults read io.github.gianhiltbrunner.rubber-stamp`).

## Build from a checkout

```sh
./build.sh             # builds build/Rubber Stamp.app
./build.sh --install   # also copies it to /Applications and starts it
./test.sh              # runs the tests
```

`test.sh` exists because with the Command Line Tools alone (no Xcode), SwiftPM does not
find the Swift Testing macro plugin; the script passes its folder to the compiler.

## License

MIT

# Contributing to Dicticus

Pull requests are welcome: bug fixes, better handling of a language or a dictation quirk, documentation.

## How a pull request is handled

Development happens in a private repository, and this public repository receives one commit per release. A pull request is therefore never merged here. Instead:

1. The pull request is reviewed here as usual.
2. Once accepted, its change is applied by hand in the private repository, and the changelog entry for the release credits you by your GitHub name.
3. The pull request is closed with a link to the release that carries the change.

## Before you open one

- Build the app as the README's "Building from Source" section describes; a change should build on macOS and, if it touches `Shared/` or `iOS/`, on iOS too.
- Keep a pull request to one change.
- Dicticus processes everything on the device. Changes that send audio or text to a server are not accepted.

## Licence

By contributing, you agree that your contribution is licensed under the Apache License 2.0, the licence of this project (see `LICENSE`).

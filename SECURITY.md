# Security policy

## Supported versions

Only the latest release gets security fixes. Update with `brew upgrade --cask halodeck`, or let a
downloaded copy update itself.

## Reporting a vulnerability

Please don't open a public issue. Report it privately on GitHub instead: go to the
[Security tab](https://github.com/disc/halodeck/security) and choose **Report a vulnerability**. Only
the maintainer sees the report.

Include what you found, how to reproduce it, and the Halodeck and macOS versions. You'll get a reply
as soon as possible, and a fix goes out in a new release before the details are made public.

## What's in scope

Halodeck needs the Accessibility permission and watches the trackpad and the mouse buttons through a
global event tap, so reports about these are especially welcome:

- anything that lets another process misuse Halodeck's permissions or its event tap;
- the update path: the signed Sparkle feed and updates, and the Homebrew cask;
- corner actions that open links, apps, Shortcuts or send key combinations.

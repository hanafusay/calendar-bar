# Calendar Bar

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS menu-bar application.

## Stack

Swift and AppKit. The user approved a standalone Swift application.

## Users and purpose

People who use Google Calendar check their current meeting and the next meeting without opening a browser.
The application is open source and installs from a DMG downloaded from GitHub Releases.

## Capabilities and constraints

Preserve the existing menu-bar behavior: today's timed events, current event first, next event countdown, completed events in gray, Meet and calendar links, manual refresh and 60-second polling.
Exclude all-day, working-location, cancelled and declined events.
Remove dependencies on SwiftBar, Python, Homebrew and an external Google CLI.
The account and credentials stay on the user's Mac. No personal events or credentials ship in the repository.
Verify the application locally before creating the public GitHub repository.
Use ad-hoc signing for the first public build. A paid Apple account is not a release prerequisite.

## Open decisions

A shared Google OAuth client requires publisher-side Google Cloud configuration.
The first-run experience depends on whether that configuration is available.
The application name Calendar Bar is an implementation default.

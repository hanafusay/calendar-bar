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
Dedicated self-signed builds are under verification. Keep the key private. The designated requirement matches the certificate and bundle identifier, but modern login Keychains independently partition self-signed applications by executable hash. Same-version restart was verified after Always Allow; update continuity failed. Do not run experimental access-metadata migration on user credentials. The update-safe design requires further verification and agreement before implementation.

## Google connection

Each user imports their own Google desktop OAuth client JSON and grants calendar read access.
The application stores client metadata and the refresh token in the local macOS Keychain.
No publisher client, credentials, or server is bundled or required.
The Calendar API is called directly from the Mac.

## Implementation default

The application name is Calendar Bar.

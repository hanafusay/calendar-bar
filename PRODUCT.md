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
Official releases use the dedicated self-signed certificate. Credential access belongs to a mutually authenticated bundled XPC service. Reuse the complete frozen signed service archive unchanged across main-application updates. The per-message requirements match the pinned certificate plus the main or service identifier. The service joins the caller's security session and accesses only the fixed credential item. Preserve stored credentials through the native initial Always Allow grant; do not rewrite credential ACLs or remove partition protections. Real application restart and 0.1.3-to-0.1.4 update passed without a repeated prompt after that initial grant. A service update or signing-key change can require reauthorization.

## Google connection

Each user imports their own Google desktop OAuth client JSON and grants calendar read access.
The application stores client metadata and the refresh token in the local macOS Keychain.
No publisher client, credentials, or server is bundled or required.
The Calendar API is called directly from the Mac.

## Implementation default

The application name is Calendar Bar.

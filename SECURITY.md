# Security policy

Report vulnerabilities through
[GitHub's private vulnerability reporting](https://github.com/gabrimatic/restart_app/security/advisories/new).
Keep the report private until a fix ships; do not open a public issue.

Include the steps to reproduce, demonstrated impact, and a suggested fix if you
have one. Reports without reproduction steps or demonstrated impact receive
lower priority. Expect acknowledgment within 48 hours.

## Scope

`restart_app` controls restart behavior on Android, iOS, web, macOS, Linux, and
Windows. Relevant reports include process lifecycle abuse, notification
permission misuse, native resource cleanup, and privilege escalation.

On iOS, the configured engine restart keeps the native process running. iOS
does not provide a public API for automatic full process restart. The package
does not provide authentication, networking, or persistent storage.

The following are outside this policy's scope:

- Issues that require a compromised device or physical access.
- Issues in third-party dependencies unrelated to this package's API.

## Supported versions

| Version | Support |
| --- | --- |
| Latest 1.10.x | Supported |
| Older releases | Upgrade to the latest supported release |

# Security Policy

## Vulnerability Reporting

Report vulnerabilities responsibly:

1. **Do not open a public issue.** Vulnerabilities stay private until a fix ships.
2. Use [GitHub's private vulnerability reporting](https://github.com/gabrimatic/restart_app/security/advisories/new) to submit.
3. Include:
   - Steps to reproduce
   - Demonstrated impact
   - Suggested fix (if any)

Reports without reproduction steps or demonstrated impact are deprioritized.

Expect acknowledgment within 48 hours.

## Scope

This package facilitates app restart or relaunch behavior across Android, iOS, web, macOS, Linux, and Windows. iOS uses an opt-in same-process Flutter engine restart because iOS does not provide a public API for automatic full process restart. It does not handle user data, authentication, networking, or persistent storage.

Reports related to process lifecycle abuse, notification permission misuse, native resource cleanup, or privilege escalation are taken seriously.

## Out of Scope

- Issues requiring a compromised device or physical access
- Issues in third-party dependencies unrelated to this package's API surface

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.8.x   | Yes       |

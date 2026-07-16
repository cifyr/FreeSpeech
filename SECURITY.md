# Security Policy

## Supported versions

FreeKit ships as a rolling release. Only the latest release receives security fixes.

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Please report security issues privately rather than opening a public issue.

- Preferred: use GitHub's private reporting through the [Report a vulnerability](https://github.com/cifyr/FreeKit/security/advisories/new) button on the repository's Security tab.
- Email: caden@cadenwarren.com

Please include:

- A description of the vulnerability and its impact.
- Steps to reproduce, and the affected FreeKit version.
- Any relevant logs or a proof of concept. FreeKit runs entirely on-device, so note the local conditions needed to trigger the issue.

You can expect an initial response within a few days. Valid reports will be fixed and released as soon as practical, and you will be credited in the advisory unless you ask to remain anonymous.

## Scope

FreeKit is a local, on-device macOS app with no backend, account system, or telemetry. Relevant reports include, for example: local privilege or sandbox-escape issues, unsafe handling of files or clipboard data, injection through the Finder Services or drag-and-drop entry points, and issues in how the app requests or uses macOS permissions (Accessibility, Microphone, Screen Recording, Camera).

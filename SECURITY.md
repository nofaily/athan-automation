# Security Policy

## Supported Versions

Security fixes are applied to the `main` branch and included in the next release. Only the latest release is supported.

| Version          | Supported |
| ---------------- | --------- |
| Latest release   | ✅        |
| Older releases   | ❌        |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions, or pull requests.**

Instead, report them privately using GitHub's [private vulnerability reporting](https://github.com/nofaily/athan-automation/security/advisories/new) (the **Report a vulnerability** button under the repository's **Security** tab).

Please include as much of the following as you can:

- A description of the issue and its potential impact
- Steps to reproduce, or a proof of concept
- Affected files or components (e.g. `athan_automation.py`, `setup.sh`, the prayer times tools, the web server configuration)
- Your environment: OS/distribution, Python version, web server

## What to Expect

This is a volunteer-maintained project, so response times are best-effort:

- You should receive an acknowledgement within a week.
- If the report is confirmed, a fix will be prepared and released, and a security advisory published. You will be credited unless you prefer otherwise.
- If the report is declined, you will get an explanation.

Please keep the details private until a fix has been released.

## Scope

Examples of issues in scope:

- `setup.sh` creating files, directories, or services with unsafe permissions or ownership
- Command injection or unsafe handling of input in the scripts or tools
- The bundled web server configuration exposing files beyond `/var/www/html/athan`

Out of scope:

- Vulnerabilities in third-party dependencies (such as pychromecast or zeroconf) — please report those upstream
- The inherent lack of authentication in the Google Cast protocol and mDNS on your local network
- Issues that require an attacker to already have root or shell access to the host

## Deployment Recommendations

Athan Automation is designed for a trusted home network. To reduce risk:

- Do not expose the web server serving `/var/www/html/athan` to the internet.
- Keep the operating system, web server, and Python dependencies up to date.
- Run the service as an unprivileged user (the default created by `setup.sh`).

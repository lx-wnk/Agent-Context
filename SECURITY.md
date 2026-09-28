# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Agent-Context, please report it privately via GitHub's security advisory form:

**[Report a vulnerability](https://github.com/lx-wnk/Agent-Context/security/advisories/new)**

If that link is unavailable, go to the repository Settings → Security → "Report a vulnerability."

Do not create a public issue for security vulnerabilities.

## Supported Versions

Only the latest released version is supported. Check [releases](https://github.com/lx-wnk/Agent-Context/releases) for the current version.

## Scope

Agent-Context is a dev tooling framework that installs files and Claude Code hooks into host projects. Its installer runs a headless setup agent with permission checks disabled that reads the host repository's docs (see [README → What the installer runs](README.md#what-the-installer-runs)). Please report any vulnerability that could execute unintended code or exfiltrate data during installation, updates, or hook execution — including instructions planted in repository content that the setup agent would follow.

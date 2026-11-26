# Security Policy

## Supported versions

Only the latest release receives security fixes. The packaged `.app` checks
GitHub for a newer release once a day and tells you when there is one; install
it when it's offered.

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue.

- Email **nahian048@gmail.com** with a description, reproduction steps, and impact, or
- Use GitHub's [private vulnerability reporting](https://github.com/jnahian/reader.md/security/advisories/new).

You can expect an acknowledgement within a few days. Once a fix is released, the
report will be credited unless you prefer to remain anonymous.

## Scope notes

Reader.md is an unsandboxed local viewer with no server component. Relevant areas:

- The bundled `WKWebView` renders markdown and is granted broad `file://` read
  access so local images resolve. It loads only bundled assets; the only network
  access is the daily update check, a request to GitHub's API for the latest
  release's version.
- The app never downloads or installs an update. Releases are DMGs on the
  GitHub release page, served over HTTPS.

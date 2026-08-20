# Security Policy

## Reporting a Vulnerability

Please report suspected vulnerabilities in this template or its default
configuration privately, rather than via a public GitHub issue:

1. Use [GitHub Security Advisories](../../security/advisories/new) for this
   repository ("Report a vulnerability" under the Security tab), or
2. Email the repository owner directly if advisories aren't available to you.

Please include:

- A description of the issue and its potential impact
- Steps to reproduce (a minimal example is ideal)
- The affected file(s)/version(s)

You should receive an acknowledgment within a few days. This is a template
project maintained on a best-effort basis, not a commercially supported
product — there's no guaranteed SLA, but reports will be reviewed and fixed
promptly where reasonable.

## Supported Versions

This is a template, not a versioned library consumers depend on — only the
latest state of the `main` branch is supported. There are no backported
security fixes to older tags.

## What's Already Scanned

Before reporting a gap, check whether it's already covered by the existing
tooling (see the [Security section of the README](README.md#security) and
`.github/workflows/security.yml`):

- **`cargo-deny`** — Rust dependency advisories (RustSec), license policy,
  banned/duplicate crates, untrusted sources
- **`hadolint`** — Dockerfile best practices
- **`gitleaks`** — secrets committed to the repo or its git history
- **`trivy config`** — Dockerfile and Kubernetes manifest misconfigurations
- **`trivy image`** — OS/package vulnerabilities in the built container image

Run `make security` locally to reproduce any of these before filing a report.
Container images published by `.github/workflows/cd.yml` are signed with
`cosign` (keyless, GitHub OIDC) — see the README's CD section for the
verification command, so you can confirm an image you're using genuinely
came from this repository's pipeline and hasn't been tampered with.

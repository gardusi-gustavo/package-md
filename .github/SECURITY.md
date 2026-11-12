# Security policy

## Reporting a vulnerability

Do not open a public issue for a security problem.

Use the repository's **Security** tab and create a private advisory, or contact
the maintainer directly through the address on the profile. Include:

- the affected repository and version;
- a minimal reproduction;
- the impact you believe it has;
- any suggested fix.

You will receive an acknowledgement, an assessment, and a disclosure plan.

## Scope

In scope: code, workflows, and configuration in this repository.

Out of scope: third-party services, social engineering, and denial-of-service
tests against shared infrastructure.

## Handling secrets

Secrets never belong in the repository, in issues, or in pull requests. If a
secret is exposed, revoke it first and rotate it second; assume it is public.

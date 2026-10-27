---
title: Authentication and authorization failures
codes: HTTP 401, HTTP 403
---
## Symptoms
The target rejects the credentials: HTTP 401 Unauthorized, HTTP 403 Forbidden, expired or
revoked API tokens, invalid client certificates, OAuth token errors.

## What it usually means
A credential expired, was rotated on the target side, or lacks a permission. Every message using
the same credential fails the same way until a person fixes it.

## Decision guidance
- Never retry unchanged: the error is deterministic and repeated failures can lock the account.
- Never change the message to work around it.
- Escalate to the integration owner with the tenant or account, the credential name used by the
  component, and the expiry date if the error reports it. Credential values must never appear in
  tickets or logs.

## Upstream fix
Store credentials in IRIS Credentials or the Wallet, track their expiry, and rotate them before
they expire. Alert on authentication errors separately from data errors.

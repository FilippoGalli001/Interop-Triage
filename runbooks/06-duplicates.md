---
title: Duplicate messages and idempotency conflicts
codes: HTTP 409, #5805
---
## Symptoms
The target reports that the record already exists (duplicate key, "already exists", conflict).

## What it usually means
The same business event was sent twice: a source resubmission, a resend after a timeout whose
first attempt actually succeeded, or two systems sending the same event.

## Decision guidance
- An exact duplicate (the target confirms identical content) must not be processed again: discard it.
- If the content differs, it is not a duplicate but an update or a conflict: escalate, never discard.
- Discarding loses the message for good, so it is confirmed by an operator unless the operations
  team made it automatic.

## Upstream fix
Make the target call idempotent (upsert or idempotency key), or treat "identical duplicate"
responses as success with ReplyCodeActions.

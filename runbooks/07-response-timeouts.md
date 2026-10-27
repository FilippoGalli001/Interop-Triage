---
title: Response timeouts (request sent, no answer)
codes: #5922, HTTP 504
---
## Symptoms
The connection worked but the target did not answer in time: read timeouts, gateway timeouts.

## What it usually means
Unlike a connection failure, the target may have received and processed the request. A blind
resend can create a duplicate.

## Decision guidance
- Before resending, check whether the target processed the first attempt when that is possible.
- If the target is idempotent, a resend is safe; otherwise prefer an operator's confirmation.

## Upstream fix
Use idempotency keys and size the response timeout to the target's real latency.

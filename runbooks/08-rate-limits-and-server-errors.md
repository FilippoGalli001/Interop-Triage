---
title: Rate limits and target server errors
codes: HTTP 429, HTTP 500, HTTP 502, HTTP 503
---
## Symptoms
The target is overloaded or failing internally: 429 Too Many Requests, 500, 502, 503.

## Decision guidance
- 429 and 503 are transient: resend later, respecting any Retry-After the target returns.
- A 500 that repeats for the same message while others succeed points to the message content:
  escalate with the target's error details.

## Upstream fix
Throttle the operation (pool size, rate limits) and agree on capacity with the target owner.

---
title: Target system unreachable (network, DNS, TLS)
codes: #6059, #6085, #6097
---
## Symptoms
An outbound operation cannot open or keep a connection: socket open failures, TLS handshake
errors, DNS resolution errors, "connection refused" or "connection timed out".

## What it usually means
The message is almost never the problem. The target host, a firewall, a certificate or the
network path is. Outages are usually short (seconds to minutes) but can last hours.

## Decision guidance
- Native retries (RetryInterval, FailureTimeout) are the first line of defense. If the alert says
  the FailureTimeout was exceeded, those retries are exhausted.
- A resend while the target is still down only repeats the failure. Resend when the target is
  reachable again, or let operations decide when the outage is long or the cause is unknown.
- Many messages failing at once with the same error are one incident, not many.
- TLS or certificate errors (for example an expired server certificate) are not transient:
  escalate to the integration owner.

## Upstream fix
Size FailureTimeout to the outages you accept (minutes, not seconds) and configure
ReplyCodeActions so connection errors are retried natively instead of failing the message.
Monitor the endpoint separately from message traffic.

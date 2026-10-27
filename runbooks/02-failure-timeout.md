---
title: FailureTimeout exceeded on a business operation
codes: <Ens>ErrFailureTimeout
---
## Symptoms
"FailureTimeout of N seconds exceeded in a component; status from last attempt was ...".

## What it usually means
The operation kept retrying a retryable error for FailureTimeout seconds and gave up. The real
cause is the "status from last attempt" part: read it and follow the runbook for that error.

## Decision guidance
- Judge the underlying error, not the timeout itself.
- A short FailureTimeout (under a minute) turns ordinary blips into failed messages: say so.

## Upstream fix
Review RetryInterval, FailureTimeout and AlertRetryGracePeriod on the component. For targets
with planned maintenance windows, consider queuing (FailureTimeout -1) with alerting on queue size.

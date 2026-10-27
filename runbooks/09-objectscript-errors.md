---
title: ObjectScript and SQL errors inside a component
codes: #5002, #5001, #5521, #5540, #5803, #5809
---
## Symptoms
The failure happens inside our own code: <UNDEFINED>, <SUBSCRIPT>, <INVALID OREF>, SQL errors,
"object not found", lock timeouts.

## What it usually means
A bug or an unexpected input in a business host, a DTL or a business rule. Lock timeouts (#5803)
can be transient under load.

## Decision guidance
- Code errors are not fixed by resending: escalate to the developers with the component, the
  error and the message id. The message stays available for resubmission after the fix.
- A single lock timeout under load can be resent once.

## Upstream fix
Add a unit test for the input that failed, then fix and redeploy the component.

---
title: Business rule violations
codes: HTTP 409, HTTP 412
---
## Symptoms
The target accepts the format but rejects the content under a business rule: negative or zero
amounts, credit limits, closed periods, invalid state transitions.

## What it usually means
The data reflects a business situation the target does not accept, or an error at the source.
Only the business can tell which.

## Decision guidance
- Never change amounts, quantities, prices or states to satisfy a rule.
- Retrying is pointless: the rule will reject the message again.
- Escalate to the business owner of the flow, quoting the rule and the values involved.

## Upstream fix
Validate the rule earlier in the flow (business process or DTL) and route rejected cases to a
work queue instead of failing at the target.

---
title: Data validation errors (format, code lists, required fields)
codes: #7209, #7201, HTTP 400, HTTP 422
---
## Symptoms
The target rejects a field: wrong format, value not in a code list, missing required value.

## Data quality policy
- Dates exchanged between systems use ISO-8601 (YYYY-MM-DD). Currencies use ISO 4217 codes,
  countries ISO 3166 codes.
- A normalization keeps the value and changes only its form: a currency or country name to its
  ISO code, letter case, surrounding spaces. Normalizations of fields listed by the operations team
  may be applied automatically.
- A correction changes or interprets the value: reordering the parts of a date, fixing a typo,
  choosing between two plausible values. Corrections always need an operator's approval, even when
  the right value looks obvious. A date that is valid in one order is not proof that the sender used
  that order; only the sender's documented convention is.
- Identifiers (order, patient, customer ids) and amounts are never changed by triage.

## Decision guidance
- Propose the corrected message with the evidence, so the operator only has to confirm.
- If two values are plausible, do not choose: escalate.

## Upstream fix
Fix the source mapping or add the conversion to the DTL, so the same error stops reaching the target.

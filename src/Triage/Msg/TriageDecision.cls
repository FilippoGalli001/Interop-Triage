/// The decision the agent submitted for an incident.
Class Triage.Msg.TriageDecision Extends Ens.Response
{

Property IncidentId As %Integer;

/// RETRY, FIX_AND_RESEND, DISCARD or ESCALATE.
Property Action As %String;

Property Reason As %String(MAXLEN = 4000);

Property Confidence As %Numeric;

/// JSON object of field name to corrected value, used by FIX_AND_RESEND.
Property Patch As %String(MAXLEN = 4000);

}

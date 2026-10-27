/// An operator's answer to an incident waiting for approval.
Class Triage.Msg.ReviewRequest Extends Ens.Request
{

Property IncidentId As %Integer;

Property Approved As %Boolean;

Property Operator As %String(MAXLEN = 128);

Property Note As %String(MAXLEN = 4000);

/// A JSON patch the operator wrote to replace the agent's, for FIX_AND_RESEND. Empty: the agent's patch.
Property Patch As %String(MAXLEN = "");

}

/// Human review queue: marks the incident as escalated and logs a warning with the diagnosis.
Class Triage.Production.EscalationOperation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As Triage.Msg.EscalationRequest, Output pResponse As Ens.Response) As %Status
{
    set incident = ##class(Triage.Data.Incident).%OpenId(pRequest.IncidentId)
    quit:'$isobject(incident) $$$ERROR($$$GeneralError, "Unknown incident " _ pRequest.IncidentId)
    set incident.Status = "ESCALATED"
    $$$LOGWARNING("Human review needed for incident " _ incident.%Id() _ " (" _ incident.SourceConfigName _ "): " _ incident.AgentReason _ $select(incident.GuardrailNote '= "": " [" _ incident.GuardrailNote _ "]", 1: ""))
    quit incident.%Save()
}

}

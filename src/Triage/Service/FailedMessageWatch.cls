/// Reports to the triage the failed messages that raised no alert (found by
/// Triage.Adapter.FailedMessageAdapter), as the alert their component would have raised. From there
/// they follow the same path: agent, rules, approval, resend or escalation.
Class Triage.Service.FailedMessageWatch Extends Ens.BusinessService
{

Parameter ADAPTER = "Triage.Adapter.FailedMessageAdapter";

Property TargetConfigName As Ens.DataType.ConfigName [ InitialExpression = "Ens.Alert" ];

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

/// pInput holds the id of the failed message's header.
Method OnProcessInput(pInput As Ens.StringContainer, Output pOutput As %RegisteredObject) As %Status
{
    set header = ##class(Ens.MessageHeader).%OpenId(pInput.StringValue)
    quit:'$isobject(header) $$$OK
    // The report joins the session of the failed message, so the Visual Trace shows it next to the failure.
    set ..%SessionId = header.SessionId
    $$$LOGINFO("Message " _ header.%Id() _ " to " _ header.TargetConfigName _ " failed without an alert: reported to the triage")
    quit ..SendRequestAsync(..TargetConfigName, ..AlertFor(header))
}

ClassMethod AlertFor(header As Ens.MessageHeader) As Ens.AlertRequest
{
    set alert = ##class(Ens.AlertRequest).%New()
    set alert.SourceConfigName = header.TargetConfigName
    set alert.SessionId = header.SessionId
    set alert.AlertText = ..ErrorText(header)
    quit alert
}

/// The error the component logged for the message: the text its alert would carry, so the error
/// signature (coalescing, replay recordings) is the same as on the alert path.
ClassMethod ErrorText(header As Ens.MessageHeader) As %String
{
    set text = "", headerId = header.%Id(), sessionId = header.SessionId, component = header.TargetConfigName
    set type = ##class(Ens.DataType.LogType).DisplayToLogical("Error")
    &sql(SELECT TOP 1 Text INTO :text FROM Ens_Util.Log
         WHERE SessionId = :sessionId AND ConfigName = :component AND MessageId = :headerId AND Type = :type
         ORDER BY %ID DESC)
    quit:(SQLCODE=0)&&(text'="") text
    quit "Message " _ headerId _ " to " _ component _ " ended in status Error, with no error in the event log"
}

}

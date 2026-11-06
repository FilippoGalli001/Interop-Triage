/// Inbound adapter that finds the failed messages nobody reported: requests in status Error whose
/// target raised no alert for them (AlertOnError is off by default) and that have no incident yet.
/// Each one is handed to the business service as the id of its message header.
Class Triage.Adapter.FailedMessageAdapter Extends Ens.InboundAdapter
{

/// Seconds a failed message must be old before it counts as unreported: a component with
/// AlertOnError raises its alert in the meantime, and the alert path handles it.
Property MinAge As %Integer [ InitialExpression = 10 ];

/// Components to watch, comma separated. Empty: all of them. The triage's own components and Ens.*
/// are never watched, so the triage cannot loop on its own failures.
Property Components As %String(MAXLEN = 1000);

/// Most failed messages handed to the business service per poll.
Property MaxPerPoll As %Integer [ InitialExpression = 5 ];

Parameter SETTINGS = "MinAge:Basic,Components:Basic,MaxPerPoll:Basic";

/// On the first poll the failures from before are history, not news: only later messages are watched.
Method OnTask() As %Status
{
    set:'$data(^Triage.Watch("startId")) ^Triage.Watch("startId") = ..LastHeaderId()
    set sc = $$$OK
    set headers = ..UnreportedFailures(^Triage.Watch("startId"), ..MinAge, ..Components, ..MaxPerPoll)
    for i=1:1:$listlength(headers) {
        set headerId = $list(headers, i)
        set sc = ..BusinessHost.ProcessInput(##class(Ens.StringContainer).%New(headerId))
        quit:$$$ISERR(sc)
        set ^Triage.Watch("seen", headerId) = $zdatetime($horolog, 3)
    }
    set ..BusinessHost.%WaitForNextCallInterval = 1
    quit sc
}

/// Ids of the failed requests after startId, at least minAge seconds old, that are watched and
/// were neither reported by an alert nor handled already.
ClassMethod UnreportedFailures(startId As %Integer, minAge As %Integer, components As %String = "", max As %Integer = 5) As %List
{
    // TimeProcessed is in UTC, with milliseconds.
    set now = $ztimestamp, days = +now, seconds = $piece(now, ",", 2) - minAge
    while seconds < 0 {
        set seconds = seconds + 86400, days = days - 1
    }
    set cutoff = $zdatetime(days _ "," _ seconds, 3, , 3)
    set watched = $listfromstring($zstrip(components, "*W"))
    set found = ""
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID, SessionId, TargetConfigName FROM Ens.MessageHeader WHERE %ID > ? AND Status = ? AND Type = ? AND TimeProcessed <= ? ORDER BY %ID",
        startId, ##class(Ens.DataType.MessageStatus).DisplayToLogical("Error"), ##class(Ens.DataType.MessageType).DisplayToLogical("Request"), cutoff)
    while ($listlength(found) < max) && rs.%Next() {
        continue:$data(^Triage.Watch("seen", rs.ID))
        continue:'..IsWatched(rs.TargetConfigName, watched)
        continue:..WasReported(rs.ID, rs.SessionId, rs.TargetConfigName)
        set found = found _ $listbuild(+rs.ID)
    }
    quit found
}

ClassMethod IsWatched(component As %String, watched As %List = "") As %Boolean
{
    quit:$extract(component, 1, 7)="Triage." 0
    quit:$extract(component, 1, 4)="Ens." 0
    quit:$listlength(watched) $listfind(watched, component)>0
    quit 1
}

/// 1 when the component raised an alert after the message failed, or an incident already has it.
ClassMethod WasReported(headerId As %Integer, sessionId As %Integer, component As %String) As %Boolean
{
    set id = ""
    &sql(SELECT TOP 1 %ID INTO :id FROM Ens.MessageHeader
         WHERE SessionId = :sessionId AND SourceConfigName = :component AND TargetConfigName = 'Ens.Alert'
           AND MessageBodyClassName = 'Ens.AlertRequest' AND %ID > :headerId)
    quit:SQLCODE=0 1
    &sql(SELECT TOP 1 %ID INTO :id FROM Triage_Data.Incident WHERE FailedHeaderId = :headerId)
    quit SQLCODE=0
}

ClassMethod LastHeaderId() As %Integer
{
    set id = 0
    &sql(SELECT MAX(%ID) INTO :id FROM Ens.MessageHeader)
    quit +id
}

}

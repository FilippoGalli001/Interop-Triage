/// Unit tests of the failed message watch (Triage.Adapter.FailedMessageAdapter). They write a few
/// message headers and an event log entry for a component that is not in the production, and delete them.
/// No LLM is needed; the running watch does not see the headers, which are younger than its MinAge.
Class Triage.Test.WatchTest Extends %UnitTest.TestCase
{

Property Created As %List;

Method Header(session As %Integer, source As %String, target As %String, bodyClass As %String, status As %String) As %Integer
{
    set header = ##class(Ens.MessageHeader).%New()
    set header.Type = ##class(Ens.DataType.MessageType).DisplayToLogical("Request")
    set header.SessionId = session
    set header.SourceConfigName = source
    set header.TargetConfigName = target
    set header.MessageBodyClassName = bodyClass
    set header.Status = ##class(Ens.DataType.MessageStatus).DisplayToLogical(status)
    set header.TimeCreated = $zdatetime($ztimestamp, 3, , 3)
    set header.TimeProcessed = header.TimeCreated
    do $$$AssertStatusOK(header.%Save(), "header saved")
    set ..Created = ..Created _ $listbuild(header.%Id())
    quit +header.%Id()
}

Method OnAfterOneTest() As %Status
{
    for i=1:1:$listlength(..Created) {
        do ##class(Ens.MessageHeader).%DeleteId($list(..Created, i))
    }
    set ..Created = ""
    quit $$$OK
}

Method TestWatchedComponents()
{
    set adapter = "Triage.Adapter.FailedMessageAdapter"
    do $$$AssertTrue($classmethod(adapter, "IsWatched", "Demo.WMS"), "any component by default")
    do $$$AssertNotTrue($classmethod(adapter, "IsWatched", "Triage.AgentOperation"), "never the triage's own components")
    do $$$AssertNotTrue($classmethod(adapter, "IsWatched", "Ens.Alert"), "nor Ens.*")
    do $$$AssertNotTrue($classmethod(adapter, "IsWatched", "Demo.WMS", $listbuild("Demo.ERP")), "only the listed components when there is a list")
    do $$$AssertNotTrue($classmethod(adapter, "IsWatched", "Triage.AgentOperation", $listbuild("Triage.AgentOperation")), "the triage stays out even when listed")
}

Method TestUnreportedFailures()
{
    set adapter = "Triage.Adapter.FailedMessageAdapter"
    set start = $classmethod(adapter, "LastHeaderId")
    set session = 900000000 + $random(1000000)
    set failed = ..Header(session, "Test.Service", "Test.Silent", "Triage.Demo.StockUpdate", "Error")
    do ..Header(session + 1, "Test.Service", "Test.Fine", "Triage.Demo.StockUpdate", "Completed")

    set found = $classmethod(adapter, "UnreportedFailures", start, 0, "", 5)
    do $$$AssertEquals(found, $listbuild(failed), "a failed request without an alert is found, a completed one is not")
    do $$$AssertEquals($classmethod(adapter, "UnreportedFailures", start, 60, "", 5), "", "not before MinAge: the alert may still come")
    do $$$AssertEquals($classmethod(adapter, "UnreportedFailures", start, 0, "Demo.ERP", 5), "", "not when the component is not in the list")

    set ^Triage.Watch("seen", failed) = 1
    do $$$AssertEquals($classmethod(adapter, "UnreportedFailures", start, 0, "", 5), "", "a reported message is reported once")
    kill ^Triage.Watch("seen", failed)

    // The component raised its alert: the alert path has it.
    do ..Header(session, "Test.Silent", "Ens.Alert", "Ens.AlertRequest", "Completed")
    do $$$AssertEquals($classmethod(adapter, "UnreportedFailures", start, 0, "", 5), "", "a failure with an alert is left to the alert path")
}

/// The alert carries the error the component logged, so an incident found by the watch has the
/// same error signature (and replay recording) as one reported by an alert.
Method TestAlertText()
{
    set session = 900000000 + $random(1000000)
    set headerId = ..Header(session, "Test.Service", "Test.Silent", "Triage.Demo.StockUpdate", "Error")
    set header = ##class(Ens.MessageHeader).%OpenId(headerId)
    set alert = ##class(Triage.Service.FailedMessageWatch).AlertFor(header)
    do $$$AssertEquals(alert.SourceConfigName, "Test.Silent", "the alert comes from the failed component")
    do $$$AssertEquals(alert.SessionId, session, "in the session of the failed message")
    do $$$AssertTrue(alert.AlertText [ "no error in the event log", "without a logged error the text says so")

    set text = "ERROR #5001: HTTP 422 Unprocessable Entity from WMS: unknown warehouse 'mil01'"
    set log = ##class(Ens.Util.Log).%New()
    set log.Type = ##class(Ens.DataType.LogType).DisplayToLogical("Error")
    set log.SessionId = session, log.ConfigName = "Test.Silent", log.MessageId = headerId
    set log.SourceClass = "Test", log.SourceMethod = "Test", log.Text = text
    set log.TimeLogged = $zdatetime($ztimestamp, 3, , 3)
    do $$$AssertStatusOK(log.%Save(), "event log entry saved")
    set alert = ##class(Triage.Service.FailedMessageWatch).AlertFor(header)
    do $$$AssertEquals(alert.AlertText, text, "the alert text is the logged error")
    do ##class(Ens.Util.Log).%DeleteId(log.%Id())
}

}

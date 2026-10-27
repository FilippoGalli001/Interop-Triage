/// Sends demo orders that exercise every failure mode of the fake ERP.
/// Run with: do ##class(Triage.Demo.Scenarios).Run()  then, after about a minute, Report().
Class Triage.Demo.Scenarios
{

/// Sends the scenarios. With reset=1, the demo data, messages and incidents are deleted first.
/// Data errors go first; then the ERP goes down for outageSeconds while three more orders arrive.
ClassMethod Run(reset As %Boolean = 1, outageSeconds As %Integer = 40) As %Status
{
    if reset do ..Reset()
    // order id, customer, amount, currency, ship date, what should happen
    set dataErrors = $listbuild(
        $listbuild("SO-1001", "C-0007", 250.00, "EUR", "2026-11-03", "accepted, no incident"),
        $listbuild("SO-1003", "C-0019", 120.00, "EUR", "21/11/2026", "date format: FIX (correction), waits for approval"),
        $listbuild("SO-1004", "C-0019", 75.00, "EURO", "2026-11-05", "currency name: FIX (normalization of Currency), automatic"),
        $listbuild("SO-1001", "C-0007", 250.00, "EUR", "2026-11-03", "exact duplicate: DISCARD, waits for approval"),
        $listbuild("SO-1005", "C-0042", 310.00, "GBP", "2026-11-06", "expired token: ESCALATE"),
        $listbuild("SO-1006", "C-0023", -120.00, "CHF", "2026-11-07", "negative amount: ESCALATE"))
    set outage = $listbuild(
        $listbuild("SO-1002", "C-0007", 980.50, "USD", "2026-11-04", "ERP down (502) beyond the native retries: agent RETRY after a delay"),
        $listbuild("SO-1007", "C-0011", 45.90, "EUR", "2026-11-08", "same outage: reuses the decision (no LLM call), resent a few seconds later"),
        $listbuild("SO-1008", "C-0011", 60.00, "EUR", "2026-11-08", "outage ends during native retries: no incident"))

    set sc = ..Send(dataErrors)
    quit:$$$ISERR(sc) sc

    // A second system with another message class: the triage is the same.
    // sku, warehouse, quantity, unit, what should happen
    set stock = $listbuild(
        $listbuild("SKU-100", "MIL01", 20, "EA", "accepted, no incident"),
        $listbuild("SKU-101", "mil01", 5, "BOX", "warehouse code in lower case: FIX (normalization of Warehouse), automatic"),
        $listbuild("SKU-999", "MIL01", 3, "EA", "unknown SKU: ESCALATE (Sku is a protected field)"))
    set sc = ..SendStock(stock)
    quit:$$$ISERR(sc) sc
    write "-- WMS in maintenance for 25 seconds", !
    do ##class(Triage.Demo.WMSOperation).StartMaintenance(25)
    set sc = ..SendStock($listbuild($listbuild("SKU-102", "ROM02", 8, "PAL", "503 with Retry-After 30: RETRY after the delay the WMS asked for")))
    quit:$$$ISERR(sc) sc
    hang 3
    write "-- ERP down for ", outageSeconds, " seconds", !
    do ##class(Triage.Demo.ERPOperation).StartOutage(outageSeconds)
    quit ..Send(outage)
}

/// A short demo for a free LLM tier: one correction waiting for approval, one automatic
/// normalization and one delayed retry through Ens.Alarm (three agent runs).
ClassMethod RunQuick() As %Status
{
    do ..Reset()
    set sc = ..Send($listbuild(
        $listbuild("SO-1003", "C-0019", 120.00, "EUR", "21/11/2026", "date format: FIX (correction), waits for approval"),
        $listbuild("SO-1004", "C-0019", 75.00, "EURO", "2026-11-05", "currency name: FIX (normalization of Currency), automatic")))
    quit:$$$ISERR(sc) sc
    write "-- WMS in maintenance for 25 seconds", !
    do ##class(Triage.Demo.WMSOperation).StartMaintenance(25)
    quit ..SendStock($listbuild($listbuild("SKU-102", "ROM02", 8, "PAL", "503 with Retry-After 30: RETRY after the delay the WMS asked for")))
}

/// Second act of the demo, after an operator reviewed the first incidents (no reset): the same
/// customers fail in the same ways, and the agent should find and cite the operators' notes.
ClassMethod RunFollowUp() As %Status
{
    quit ..Send($listbuild(
        $listbuild("SO-1103", "C-0019", 99.00, "EUR", "28/11/2026", "same customer, same date format: agent cites the approved incident"),
        $listbuild("SO-1105", "C-0042", 150.00, "GBP", "2026-11-12", "same expired token: agent cites the operator's resolution")))
}

ClassMethod SendStock(updates As %List) As %Status
{
    set sc = ##class(Ens.Director).CreateBusinessService("Demo.StockService", .service)
    quit:$$$ISERR(sc) sc
    for i=1:1:$listlength(updates) {
        set s = $list(updates, i)
        set update = ##class(Triage.Demo.StockUpdate).%New()
        set update.Sku = $list(s, 1)
        set update.Warehouse = $list(s, 2)
        set update.Quantity = $list(s, 3)
        set update.Unit = $list(s, 4)
        write update.Sku, ": ", $list(s, 5), !
        set sc = service.ProcessInput(update)
        quit:$$$ISERR(sc)
        hang 0.5
    }
    quit sc
}

ClassMethod Send(orders As %List) As %Status
{
    set sc = ##class(Ens.Director).CreateBusinessService("Demo.OrderService", .service)
    quit:$$$ISERR(sc) sc
    for i=1:1:$listlength(orders) {
        set s = $list(orders, i)
        set order = ##class(Triage.Demo.OrderRequest).%New()
        set order.OrderId = $list(s, 1)
        set order.CustomerId = $list(s, 2)
        set order.Amount = $list(s, 3)
        set order.Currency = $list(s, 4)
        set order.ShipDate = $list(s, 5)
        write order.OrderId, ": ", $list(s, 6), !
        set sc = service.ProcessInput(order)
        quit:$$$ISERR(sc)
        // Keep the original order ahead of its duplicate.
        hang 0.5
    }
    quit sc
}

/// Deletes the demo data and restarts the production with empty queues, messages and event log.
ClassMethod Reset()
{
    do ##class(Ens.Director).StopProduction(10, 1)
    do ##class(Ens.Director).CleanProduction()
    do ##class(Ens.MessageHeader).Purge(.deleted, 0, 0, 1)
    do ##class(Ens.Util.Log).Purge(.deleted, 0)
    do ##class(Ens.Director).StartProduction(##class(Triage.Setup).#PRODUCTION)
    kill ^Triage.Demo, ^Triage.Resend
    do ##class(Triage.Demo.ERPOrder).%KillExtent()
    do ##class(Triage.Demo.WMSMovement).%KillExtent()
    do ##class(Triage.Data.Incident).%KillExtent()
    do ##class(Triage.Data.ToolCallLog).%KillExtent()
    // The incident memory refers to the deleted incidents: start it again too.
    do ##class(Triage.Knowledge.Base).Open("incidents", .kb)
    do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM TriageKB.Incidents")
}

/// Prints one block per incident: what the agent proposed and what was done, then the ERP orders.
ClassMethod Report()
{
    set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT %ID, AttemptNumber, LeaderIncidentId, RetryDelay, AgentAction, AgentFixType, AgentConfidence, AgentPatch, FinalAction, Status, GuardrailNote, AgentReason, UpstreamRecommendation, PromptTokens, CompletionTokens, ToolCalls, AgentDurationMs, MessageBody FROM Triage_Data.Incident ORDER BY %ID")
    while rs.%Next() {
        write "#", rs.ID, " attempt ", rs.AttemptNumber, " ", rs.MessageBody, !
        write "   agent: ", rs.AgentAction, $select(rs.AgentFixType'="": "/" _ rs.AgentFixType, 1: ""), " (", rs.AgentConfidence, ")"
        write:rs.AgentAction="FIX_AND_RESEND" " patch ", rs.AgentPatch
        write:rs.RetryDelay'="" " after ", rs.RetryDelay, " s"
        write "  final: ", rs.FinalAction, "  status: ", rs.Status, !
        write:rs.LeaderIncidentId'="" "   reused decision of incident ", rs.LeaderIncidentId, " (no LLM call)", !
        write:rs.GuardrailNote'="" "   rules: ", rs.GuardrailNote, !
        write "   reason: ", rs.AgentReason, !
        write:rs.UpstreamRecommendation'="" "   upstream: ", rs.UpstreamRecommendation, !
        write:rs.ToolCalls'="" "   tokens: ", rs.PromptTokens, "+", rs.CompletionTokens, "  tool calls: ", rs.ToolCalls, "  ", rs.AgentDurationMs, " ms", !
    }
    write !, "ERP orders:"
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT OrderId, Currency, ShipDate FROM Triage_Demo.ERPOrder ORDER BY OrderId")
    while rs.%Next() {
        write " ", rs.OrderId, "/", rs.Currency, "/", rs.ShipDate
    }
    write !, "WMS movements:"
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Sku, Warehouse, Quantity, Unit FROM Triage_Demo.WMSMovement ORDER BY Sku")
    while rs.%Next() {
        write " ", rs.Sku, "/", rs.Warehouse, "/", rs.Quantity, rs.Unit
    }
    write !
}

}

/// Sends stock movements to the fake WMS (Triage.Demo.MockAPI) over HTTP.
Class Triage.Demo.WMSOperation Extends Triage.Demo.HTTPOperation
{

Parameter TARGETNAME = "WMS";

Method OnMessage(pRequest As Triage.Demo.StockUpdate, Output pResponse As Ens.Response) As %Status
{
    quit ..PostJSON(##class(Triage.Util).ToJSON(pRequest))
}

/// Puts the WMS in maintenance for the given number of seconds: it answers 503 with Retry-After.
ClassMethod StartMaintenance(seconds As %Integer)
{
    set ^Triage.Demo("wmsMaintenanceUntil") = ##class(Triage.Demo.ERPOperation).Now() + seconds
}

}

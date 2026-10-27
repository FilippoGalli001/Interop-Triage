/// Sends orders to the fake ERP (Triage.Demo.MockAPI) over HTTP.
Class Triage.Demo.ERPOperation Extends Triage.Demo.HTTPOperation
{

Parameter TARGETNAME = "ERP";

Method OnMessage(pRequest As Triage.Demo.OrderRequest, Output pResponse As Ens.Response) As %Status
{
    quit ..PostJSON(##class(Triage.Util).ToJSON(pRequest))
}

/// Seconds since 1840, comparable across processes.
ClassMethod Now() As %Integer
{
    quit $piece($horolog, ",") * 86400 + $piece($horolog, ",", 2)
}

/// Takes the ERP application server down for the given number of seconds: its gateway answers 502.
ClassMethod StartOutage(seconds As %Integer)
{
    set ^Triage.Demo("outageUntil") = ..Now() + seconds
}

}

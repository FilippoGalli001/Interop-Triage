/// An operations runbook loaded from the runbooks folder, with the error codes it covers.
Class Triage.Knowledge.Runbook Extends %Persistent
{

/// File name, for example 01-network-connectivity.md.
Property Name As %String(MAXLEN = 256) [ Required ];

Property Title As %String(MAXLEN = 512);

/// Comma-separated codes from the front matter: IRIS errors (#6059, <Ens>ErrFailureTimeout) or HTTP statuses (HTTP 401).
Property Codes As %String(MAXLEN = 1000);

Property Body As %String(MAXLEN = 32000);

Index NameIdx On Name [ Unique ];

/// True when the runbook lists the code (compared without spaces and case).
Method Covers(code As %String) As %Boolean
{
    set codes = $listfromstring($zconvert($zstrip(..Codes, "*W"), "U"))
    quit ''$listfind(codes, $zconvert($zstrip(code, "*W"), "U"))
}

}

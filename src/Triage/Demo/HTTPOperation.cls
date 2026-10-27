/// Base of the demo operations: posts the message as JSON with EnsLib.HTTP.OutboundAdapter and turns
/// an HTTP error into a status that says what the target answered.
Class Triage.Demo.HTTPOperation Extends Ens.BusinessOperation [ Abstract ]
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

/// Name of the target system in error messages.
Parameter TARGETNAME;

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// HTTP statuses that the operation retries by itself (RetryInterval, FailureTimeout) before
/// failing the message. Other HTTP errors fail at once and go to the triage.
Property RetryableStatusCodes As %String [ InitialExpression = "502,504" ];

Parameter SETTINGS = "RetryableStatusCodes:Basic";

/// Posts the body to the adapter's URL. Statuses in RetryableStatusCodes are retried natively;
/// connection errors keep the adapter's own retry behavior; other HTTP errors go to the triage.
Method PostJSON(body As %DynamicObject) As %Status
{
    set request = ##class(%Net.HttpRequest).%New()
    set request.ContentType = "application/json"
    set request.ContentCharset = "utf-8"
    do request.EntityBody.Write(body.%ToJSON())
    set sc = ..Adapter.SendFormDataArray(.response, "POST", request)
    if $isobject(response) && (response.StatusCode >= 400) {
        set ..Retry = ''$listfind($listfromstring($zstrip(..RetryableStatusCodes, "*W")), response.StatusCode)
        set retryAfter = response.GetHeader("RETRY-AFTER")
        quit $$$ERROR($$$GeneralError, "HTTP " _ response.StatusCode _ " " _ response.ReasonPhrase _ " from " _ ..#TARGETNAME _ ": " _ ..ErrorText(response) _ $select(retryAfter '= "": ". Retry-After: " _ retryAfter, 1: ""))
    }
    quit sc
}

/// The "error" field of a JSON error body, or the body itself.
Method ErrorText(response As %Net.HttpResponse) As %String
{
    set text = ""
    if $isobject(response.Data) {
        do response.Data.Rewind()
        set text = response.Data.Read(4000)
    }
    try {
        set text = ##class(%DynamicObject).%FromJSON(text).error
    } catch {
    }
    quit text
}

}

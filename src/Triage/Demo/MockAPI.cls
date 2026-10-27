/// The fake ERP and WMS, as real HTTP endpoints at /demo/api (password authentication).
/// The demo operations call them with EnsLib.HTTP.OutboundAdapter, so every failure the triage sees
/// is a real HTTP status from a real adapter: 401, 404, 409, 422, and 503 with Retry-After.
Class Triage.Demo.MockAPI Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

Parameter UseSession = 0;

Parameter CURRENCIES = "EUR,USD,GBP,CHF";

/// Tenants whose ERP API token has expired.
Parameter EXPIREDTENANTS = "C-0042";

Parameter SKUS = "SKU-100,SKU-101,SKU-102,SKU-103";

Parameter WAREHOUSES = "MIL01,ROM02";

Parameter UNITS = "EA,BOX,PAL";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/erp/orders" Method="POST" Call="CreateOrder"/>
  <Route Url="/wms/movements" Method="POST" Call="CreateMovement"/>
</Routes>
}

ClassMethod CreateOrder() As %Status
{
    if ##class(Triage.Demo.ERPOperation).Now() < $get(^Triage.Demo("outageUntil")) {
        quit ..Fail(502, "Bad Gateway", "ERP application server unavailable (upstream connect error)")
    }
    set order = ..Body()
    quit:'$isobject(order) ..Fail(400, "Bad Request", "body must be a JSON object")
    if $listfind($listfromstring(..#EXPIREDTENANTS), order.CustomerId) {
        quit ..Fail(401, "Unauthorized", "API token for tenant " _ order.CustomerId _ " expired on 2026-10-01")
    }
    if order.ShipDate '?4N1"-"2N1"-"2N {
        quit ..Fail(422, "Unprocessable Entity", "field 'ShipDate' must be ISO-8601 (YYYY-MM-DD), got '" _ order.ShipDate _ "'")
    }
    if '$listfind($listfromstring(..#CURRENCIES), order.Currency) {
        quit ..Fail(422, "Unprocessable Entity", "unsupported currency '" _ order.Currency _ "' (supported: " _ ..#CURRENCIES _ ")")
    }
    if order.Amount <= 0 {
        quit ..Fail(409, "Conflict", "business rule BR-12 violated, order amount must be positive (got " _ order.Amount _ ")")
    }
    set existing = ##class(Triage.Demo.ERPOrder).OrderIdIdxOpen(order.OrderId)
    if $isobject(existing) {
        set same = (existing.CustomerId = order.CustomerId) && (existing.Amount = order.Amount) && (existing.Currency = order.Currency) && (existing.ShipDate = order.ShipDate)
        quit ..Fail(409, "Conflict", "order " _ order.OrderId _ " already exists (created " _ existing.ReceivedAt _ ") with " _ $select(same: "identical", 1: "different") _ " content")
    }
    set row = ##class(Triage.Demo.ERPOrder).%New()
    set row.OrderId = order.OrderId
    set row.CustomerId = order.CustomerId
    set row.Amount = order.Amount
    set row.Currency = order.Currency
    set row.ShipDate = order.ShipDate
    set sc = row.%Save()
    quit:$$$ISERR(sc) ..Fail(500, "Internal Server Error", $system.Status.GetErrorText(sc))
    set %response.Status = "201 Created"
    write {"orderId": (row.OrderId), "status": "created"}.%ToJSON()
    quit $$$OK
}

ClassMethod CreateMovement() As %Status
{
    if ##class(Triage.Demo.ERPOperation).Now() < $get(^Triage.Demo("wmsMaintenanceUntil")) {
        do %response.SetHeader("Retry-After", 30)
        quit ..Fail(503, "Service Unavailable", "scheduled maintenance in progress")
    }
    set movement = ..Body()
    quit:'$isobject(movement) ..Fail(400, "Bad Request", "body must be a JSON object")
    if '$listfind($listfromstring(..#SKUS), movement.Sku) {
        quit ..Fail(404, "Not Found", "SKU '" _ movement.Sku _ "' is not in the item master")
    }
    if '$listfind($listfromstring(..#WAREHOUSES), movement.Warehouse) {
        quit ..Fail(422, "Unprocessable Entity", "unknown warehouse code '" _ movement.Warehouse _ "' (valid: " _ ..#WAREHOUSES _ ", case-sensitive)")
    }
    if '$listfind($listfromstring(..#UNITS), movement.Unit) {
        quit ..Fail(422, "Unprocessable Entity", "unit of measure '" _ movement.Unit _ "' not supported (valid: " _ ..#UNITS _ ")")
    }
    set row = ##class(Triage.Demo.WMSMovement).%New()
    set row.Sku = movement.Sku
    set row.Warehouse = movement.Warehouse
    set row.Quantity = movement.Quantity
    set row.Unit = movement.Unit
    set sc = row.%Save()
    quit:$$$ISERR(sc) ..Fail(500, "Internal Server Error", $system.Status.GetErrorText(sc))
    set %response.Status = "201 Created"
    write {"movementId": (row.%Id()), "status": "created"}.%ToJSON()
    quit $$$OK
}

ClassMethod Body() As %DynamicObject
{
    set body = ""
    try {
        set body = ##class(%DynamicObject).%FromJSON(%request.Content)
    } catch {
    }
    quit body
}

/// Answers with an HTTP error status and {"error": message}.
ClassMethod Fail(code As %Integer, reason As %String, message As %String) As %Status
{
    set %response.Status = code _ " " _ reason
    write {"error": (message)}.%ToJSON()
    quit $$$OK
}

}

/// A sales order sent from the demo order service to the fake ERP.
Class Triage.Demo.OrderRequest Extends Ens.Request
{

Property OrderId As %String;

Property CustomerId As %String;

Property Amount As %Numeric(SCALE = 2);

/// ISO 4217 code expected by the ERP (EUR, USD, GBP, CHF).
Property Currency As %String;

/// The ERP expects ISO-8601 dates (YYYY-MM-DD).
Property ShipDate As %String;

}

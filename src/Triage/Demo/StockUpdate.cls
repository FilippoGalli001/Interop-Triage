/// A stock movement sent to the fake warehouse management system (WMS).
Class Triage.Demo.StockUpdate Extends Ens.Request
{

Property Sku As %String;

/// Warehouse code, upper case (MIL01, ROM02).
Property Warehouse As %String;

/// Positive for goods received, negative for goods shipped.
Property Quantity As %Integer;

/// Unit of measure: EA, BOX or PAL.
Property Unit As %String;

}

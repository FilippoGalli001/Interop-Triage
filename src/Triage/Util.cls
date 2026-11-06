/// Helpers shared by the triage components.
Class Triage.Util
{

/// Returns the public, stored properties of any object as a dynamic object.
ClassMethod ToJSON(obj As %RegisteredObject) As %DynamicObject
{
    set json = {}
    quit:'$isobject(obj) json
    set names = ..PropertyNames($classname(obj))
    for i=1:1:$listlength(names) {
        set name = $list(names, i)
        set value = $property(obj, name)
        continue:$isobject(value)
        do json.%Set(name, value)
    }
    quit json
}

/// Names of the properties an agent may see and patch: public, stored, not inherited from Ens.
ClassMethod PropertyNames(className As %String) As %List
{
    set names = ""
    set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ? AND Private = 0 AND Internal = 0 AND Calculated = 0 AND Transient = 0 AND Name NOT LIKE '\%%' ESCAPE '\' AND (Origin NOT LIKE 'Ens.%') ORDER BY SequenceNumber",
        className)
    while rs.%Next() {
        set names = names_$listbuild(rs.Name)
    }
    quit names
}

/// Reads an environment variable of the IRIS process.
ClassMethod Env(name As %String, default As %String = "") As %String
{
    set value = $system.Util.GetEnviron(name)
    quit $select(value = "": default, 1: value)
}

/// An error text cut to max characters. Some provider errors repeat every failed attempt and run to
/// tens of kilobytes: the start says what happened.
ClassMethod Short(text As %String, max As %Integer = 500) As %String
{
    quit:$length(text)<=max text
    quit $extract(text, 1, max - 1) _ $char(8230)
}

}

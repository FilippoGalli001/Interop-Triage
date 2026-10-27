/// Installation and development helpers.
Class Triage.Setup
{

Parameter PRODUCTION = "Triage.Production.Main";

Parameter WEBDIR = "/home/irisowner/dev/web";

/// Recorded live decisions used by replay mode, shipped in the repository.
Parameter RECORDINGS = "/home/irisowner/dev/recordings/decisions.json";

/// Run once at image build time: indexes the runbooks (which also downloads the FastEmbed model
/// into the image, so no download is needed at run time) and marks the production to start with IRIS.
ClassMethod Install() As %Status
{
    set sc = ##class(Triage.Knowledge.Base).LoadRunbooks()
    quit:$$$ISERR(sc) sc
    set sc = ..CreateWebApps()
    quit:$$$ISERR(sc) sc
    set sc = ##class(Triage.Data.Recording).Import(..#RECORDINGS)
    quit:$$$ISERR(sc) sc
    // The demo operations authenticate to the fake ERP and WMS with these interoperability credentials.
    set sc = ##class(Ens.Config.Credentials).SetCredential("DemoTargets", "_SYSTEM", "SYS", 1)
    quit:$$$ISERR(sc) sc
    quit ##class(Ens.Director).SetAutoStart(..#PRODUCTION)
}

/// Creates the web applications: /triage serves the static dashboard page (no data in it),
/// /triage/api is its REST API, /demo/api the fake ERP and WMS, /mcp/triage the MCP Server.
/// All but the static page use password authentication.
ClassMethod CreateWebApps() As %Status
{
    new $namespace
    set namespace = $namespace
    set $namespace = "%SYS"
    set page("NameSpace") = namespace
    set page("Path") = ..#WEBDIR
    set page("DispatchClass") = ""
    set page("ServeFiles") = 1
    set page("Description") = "Interop triage dashboard (static page)"
    // 64 = unauthenticated: the page asks for the IRIS credentials and sends them to the API.
    set page("AutheEnabled") = 64
    set page("Enabled") = 1
    set sc = ..SaveWebApp("/triage", .page)
    quit:$$$ISERR(sc) sc

    set api("NameSpace") = namespace
    set api("DispatchClass") = "Triage.API.REST"
    set api("Description") = "Interop triage dashboard API"
    // 32 = password authentication
    set api("AutheEnabled") = 32
    set api("Enabled") = 1
    set sc = ..SaveWebApp("/triage/api", .api)
    quit:$$$ISERR(sc) sc

    set mock("NameSpace") = namespace
    set mock("DispatchClass") = "Triage.Demo.MockAPI"
    set mock("Description") = "Fake ERP and WMS called by the demo production"
    set mock("AutheEnabled") = 32
    set mock("Enabled") = 1
    set sc = ..SaveWebApp("/demo/api", .mock)
    quit:$$$ISERR(sc) sc

    // MCP Server for operators' AI assistants (Type 18), reached through iris-mcp-server.
    set mcp("NameSpace") = namespace
    set mcp("DispatchClass") = "Triage.MCP.Service"
    set mcp("Description") = "Triage tools for an operator's AI assistant"
    set mcp("Type") = 18
    set mcp("AutheEnabled") = 32
    set mcp("Enabled") = 1
    quit ..SaveWebApp("/mcp/triage", .mcp)
}

ClassMethod SaveWebApp(name As %String, ByRef props) As %Status
{
    quit:##class(Security.Applications).Exists(name) ##class(Security.Applications).Modify(name, .props)
    quit ##class(Security.Applications).Create(name, .props)
}

/// Writes the recordings of the live runs to the repository file used by replay mode.
ClassMethod ExportRecordings() As %Status
{
    quit ##class(Triage.Data.Recording).Export(..#RECORDINGS)
}

/// Runs the unit tests of the compiled Triage.Test package.
/// docker exec -it iris-triage iris session IRIS -U TRIAGE "##class(Triage.Setup).RunTests()"
ClassMethod RunTests() As %Status
{
    set ^UnitTestRoot = "/tmp"
    set sc = $$$OK
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledClass WHERE Name %STARTSWITH 'Triage.Test.'")
    while rs.%Next() {
        set sc = $$$ADDSC(sc, ##class(%UnitTest.Manager).DebugRunTestCase("", rs.Name, "", ""))
    }
    quit sc
}

/// Development: reloads the mounted sources and restarts the production.
/// docker exec -it iris-triage iris session IRIS -U TRIAGE "##class(Triage.Setup).Reload()"
ClassMethod Reload() As %Status
{
    set sc = $system.OBJ.LoadDir("/home/irisowner/dev/src", "ck", .errors, 1)
    quit:$$$ISERR(sc) sc
    do ##class(Ens.Director).StopProduction(10, 1)
    quit ##class(Ens.Director).StartProduction(..#PRODUCTION)
}

}

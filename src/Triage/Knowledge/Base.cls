/// The agent's knowledge: the operations runbooks and the memory of incidents reviewed by operators.
/// Both are AI Hub knowledge bases (FastEmbed embeddings in an IRIS vector table).
Class Triage.Knowledge.Base
{

Parameter RUNBOOKDIR = "/home/irisowner/dev/runbooks";

/// Opens a knowledge base: "runbooks" or "incidents". The vector tables are created on first use.
ClassMethod Open(name As %String, Output kb As %AI.RAG.KnowledgeBase) As %Status
{
    set kb = ""
    try {
        set embedding = ##class(%AI.RAG.Embedding.FastEmbed).Create()
        set store = ##class(%AI.RAG.VectorStore.IRIS).%New()
        set store.TableName = $case(name, "runbooks": "TriageKB.Runbooks", "incidents": "TriageKB.Incidents")
        set store.Dimensions = 384
        set store.ModelName = "AllMiniLML6V2"
        $$$ThrowOnError(store.Build())
        if name = "runbooks" {
            set kb = ##class(%AI.RAG.KnowledgeBase).%New("search_runbooks",
                "Search the operations runbooks: company procedures for handling integration failures (connectivity, credentials, data validation, business rules, duplicates, escalation). Query in English with the symptoms or the error.")
        } else {
            set kb = ##class(%AI.RAG.KnowledgeBase).%New("search_incidents",
                "Search past incidents that an operator reviewed (approved, rejected or resolved), with the operator's notes. Use it to reuse what people decided for similar failures.")
        }
        set kb.TopK = 3
        $$$ThrowOnError(kb.Build(embedding, store))
        set sc = $$$OK
    } catch ex {
        set sc = ex.AsStatus()
    }
    quit sc
}

/// Gives the agent the search tools of both knowledge bases.
ClassMethod AddToAgent(agent As %AI.Agent) As %Status
{
    for name = "runbooks", "incidents" {
        set sc = ..Open(name, .kb)
        quit:$$$ISERR(sc)
        set sc = kb.AddToAgent(agent)
        quit:$$$ISERR(sc)
    }
    quit sc
}

/// Loads every runbook of the folder into Triage.Knowledge.Runbook and indexes it, one section per document.
ClassMethod LoadRunbooks(dir As %String = {..#RUNBOOKDIR}) As %Status
{
    set sc = ..Open("runbooks", .kb)
    quit:$$$ISERR(sc) sc
    do ##class(Triage.Knowledge.Runbook).%KillExtent()
    // Dynamic SQL: the vector table is created at run time by AI Hub, not by a class.
    do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM TriageKB.Runbooks")

    set docs = []
    set file = $zsearch(##class(%File).NormalizeFilename("*.md", dir))
    while file '= "" {
        set sc = ..ReadRunbook(file, .runbook)
        quit:$$$ISERR(sc)
        set sc = runbook.%Save()
        quit:$$$ISERR(sc)
        set sections = ..Sections(runbook.Body)
        for i=1:1:$listlength(sections) {
            set section = $list(sections, i)
            set heading = $piece(section, $char(10))
            do docs.%Push([("Runbook: " _ runbook.Title _ " > " _ heading _ $char(10) _ $piece(section, $char(10), 2, *)),
                {"source": (runbook.Name _ "#" _ i), "runbook": (runbook.Name), "title": (runbook.Title), "section": (heading), "codes": (runbook.Codes)}])
        }
        set file = $zsearch("")
    }
    quit:$$$ISERR(sc) sc
    set chunks = kb.AddDocuments(docs)
    write "Indexed ", chunks, " runbook sections", !
    quit $$$OK
}

/// Parses a runbook: front matter (title, codes) then the Markdown body.
ClassMethod ReadRunbook(path As %String, Output runbook As Triage.Knowledge.Runbook) As %Status
{
    set stream = ##class(%Stream.FileCharacter).%New()
    set stream.TranslateTable = "UTF8"
    set sc = stream.LinkToFile(path)
    quit:$$$ISERR(sc) sc
    set runbook = ##class(Triage.Knowledge.Runbook).%New()
    set runbook.Name = ##class(%File).GetFilename(path)
    set inFrontMatter = 0, body = ""
    while 'stream.AtEnd {
        set line = $zstrip(stream.ReadLine(), ">", $char(13))
        if line = "---" {
            set inFrontMatter = 'inFrontMatter
            continue
        }
        if inFrontMatter {
            set:$piece(line, ":")="title" runbook.Title = $zstrip($piece(line, ":", 2, *), "<>W")
            set:$piece(line, ":")="codes" runbook.Codes = $zstrip($piece(line, ":", 2, *), "<>W")
            continue
        }
        set body = body _ line _ $char(10)
    }
    set runbook.Body = body
    quit $$$OK
}

/// Splits a Markdown body at its "## " headings; each element starts with the heading text.
ClassMethod Sections(body As %String) As %List
{
    set sections = ""
    set parts = $listfromstring($char(10) _ body, $char(10) _ "## ")
    for i=2:1:$listlength(parts) {
        set sections = sections _ $listbuild($zstrip($list(parts, i), "<>W"))
    }
    quit sections
}

/// Indexes an incident an operator reviewed or resolved, so later triage can learn from it.
ClassMethod RememberIncident(incident As Triage.Data.Incident) As %Status
{
    quit:incident.ReviewedBy="" $$$OK
    set sc = ..Open("incidents", .kb)
    quit:$$$ISERR(sc) sc
    set text = "Component: " _ incident.SourceConfigName _ $char(10) _
        "Error: " _ incident.AlertText _ $char(10) _
        "Message: " _ incident.MessageClass _ " " _ incident.MessageBody _ $char(10) _
        "Agent proposed: " _ incident.AgentAction _ $select(incident.AgentPatch'="" && (incident.AgentPatch'="{}"): " " _ incident.AgentPatch, 1: "") _ ". " _ incident.AgentReason _ $char(10) _
        $select(incident.OperatorPatch'="": "Operator changed the patch to: " _ incident.OperatorPatch _ $char(10), 1: "") _
        "Outcome: " _ incident.Status _ " (" _ incident.FinalAction _ ") by " _ incident.ReviewedBy _ " on " _ incident.ReviewedAt _ $char(10) _
        "Operator note: " _ incident.ReviewNote
    set chunks = kb.ReindexDocument("incident-" _ incident.%Id(), text,
        {"incident": (incident.%Id()), "component": (incident.SourceConfigName), "outcome": (incident.Status), "action": (incident.FinalAction)})
    quit $$$OK
}

}

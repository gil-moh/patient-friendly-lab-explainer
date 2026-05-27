Include %occStatus

Class Sample.AI.Examples.LabRetrieverDemo Extends %RegisteredObject
{

/// Demo for Phase 1 grounding core.
ClassMethod Demo(panel As %String = "a1c", query As %String = "What does high A1c mean?", topK As %Integer = 3) As %Status
{
    Try {
        Set result = ##class(Sample.AI.Tools.LabEducationRetriever).GetExplanationSnippets(panel, query, topK)

        Write !, "Lab Education Retriever Demo", !
        Write "panel=", result.%Get("panel"), !
        Write "query=", result.%Get("query"), !
        Write "mode=", result.%Get("mode"), !
        Write "status=", result.%Get("status"), !

        Set snippets = result.%Get("snippets")
        If '$ISOBJECT(snippets) || (snippets.%Size()=0) {
            Write "snippets=(none)", !
            Return $$$OK
        }

        Write !, "snippets", !
        For i=0:1:(snippets.%Size()-1) {
            Set one = snippets.%Get(i)
            Write "- [", i+1, "] source=", one.%Get("source"), " score=", one.%Get("score"), !
            Write "  ", one.%Get("text"), !
        }

        Return $$$OK
    } Catch ex {
        Write !, "Demo failed: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
}

}

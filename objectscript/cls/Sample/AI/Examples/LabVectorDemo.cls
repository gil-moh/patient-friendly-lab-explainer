Include %occStatus

Class Sample.AI.Examples.LabVectorDemo Extends %RegisteredObject
{

/// Demonstrates switching the retriever to true vector mode.
ClassMethod Demo(panel As %String = "a1c", query As %String = "What does high A1c mean?", topK As %Integer = 3) As %Status
{
    Try {
        Set result = ##class(Sample.AI.Tools.LabEducationRetriever).GetExplanationSnippets(panel, query, topK)

        Write !, "Lab Vector Demo", !
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
        Write !, "Vector demo failed: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
}

}

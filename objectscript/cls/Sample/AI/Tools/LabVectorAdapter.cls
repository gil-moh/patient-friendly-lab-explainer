Include %occStatus

Class Sample.AI.Tools.LabVectorAdapter Extends %RegisteredObject
{

Parameter TABLENAME = "Sample.LabEducationVec";
Parameter TOOLNAME = "search_lab_edu";
Parameter TOOLDESC = "Patient lab education snippets grounded in curated sources";

/// True vector retrieval adapter for LabEducationRetriever.
/// Returns snippet objects in the same contract shape used by fallback mode.
ClassMethod SearchEducationalSnippets(panel As %String, query As %String, topK As %Integer = 3) As %DynamicArray
{
    Set out = []
    Set k = $Select(topK<1:1, 1:topK)

    Set kb = ""
    Set sc = ..PrepareKnowledgeBase(.kb, k)
    If $$$ISERR(sc) {
        Return out
    }

    Set agent = ##class(%AI.Agent).%New()
    Set sc = kb.AddToAgent(agent)
    If $$$ISERR(sc) {
        Return out
    }

    Set args = {}
    Set args.query = query

    Try {
        Set raw = agent.ToolManager.ExecuteTool(..#TOOLNAME, args)
    } Catch ex {
        Return out
    }

    If '$ISOBJECT(raw) {
        Return out
    }

    Set hits = raw.%Get("value")
    If '$ISOBJECT(hits) || (hits.%Size()=0) {
        Return out
    }

    Set normalizedPanel = ..NormalizePanel(panel)
    Set kept = 0
    For i=0:1:(hits.%Size()-1) {
        Quit:kept'<k
        Set hit = hits.%Get(i)
        If '$ISOBJECT(hit) {
            Continue
        }

        Set metadata = hit.%Get("metadata")
        Set hitPanel = "general"
        Set hitSource = "knowledge-base"
        If $ISOBJECT(metadata) {
            Set candidatePanel = ..NormalizePanel(metadata.%Get("panel"))
            If candidatePanel '= "" {
                Set hitPanel = candidatePanel
            }
            Set sourceValue = $ZSTRIP(metadata.%Get("source"), "<>W")
            If sourceValue '= "" {
                Set hitSource = sourceValue
            }
        }

        If (hitPanel '= "general") && (hitPanel '= normalizedPanel) {
            Continue
        }

        Set text = $ZSTRIP(hit.%Get("text"), "<>W")
        If text = "" {
            Continue
        }

        Set score = +hit.%Get("score")
        Set snippet = {}
        Set snippet.panel = hitPanel
        Set snippet.source = hitSource
        Set snippet.score = score
        Set snippet.text = text
        Do out.%Push(snippet)
        Set kept = kept + 1
    }

    Return out
}

ClassMethod EnsureKnowledgeBase() As %Status [ Internal ]
{
    Set kb = ""
    Return ..PrepareKnowledgeBase(.kb, 3)
}

ClassMethod PrepareKnowledgeBase(ByRef kb As %AI.RAG.KnowledgeBase, topK As %Integer = 3) As %Status [ Internal ]
{
    Try {
        Set emb = ##class(%AI.RAG.Embedding.FastEmbed).Create()

        Set fields = []
        Set f1 = {}
        Set f1.name = "panel"
        Set f1.type = "varchar(20)"
        Set f1.description = "Lab panel key"
        Do fields.%Push(f1)

        Set f2 = {}
        Set f2.name = "topic"
        Set f2.type = "varchar(80)"
        Set f2.description = "Educational topic"
        Do fields.%Push(f2)

        Set vs = ##class(%AI.RAG.VectorStore.IRIS).%New()
        Set vs.TableName = ..#TABLENAME
        Set vs.Dimensions = emb.Dimensions
        Set vs.ModelName = emb.ModelName
        Set sc = vs.Build(fields)
        $$$ThrowOnError(sc)

        Set kb = ..CreateKnowledgeBase(topK)
        Set sc = kb.Build(emb, vs)
        $$$ThrowOnError(sc)

        Set count = ..GetVectorCount(..#TABLENAME)
        If count=0 {
            Set docs = ..SeedDocuments()
            Do kb.AddDocuments(docs)
        }

        Return $$$OK
    } Catch ex {
        Return ex.AsStatus()
    }
}

ClassMethod CreateKnowledgeBase(topK As %Integer = 3) As %AI.RAG.KnowledgeBase [ Internal ]
{
    Set kb = ##class(%AI.RAG.KnowledgeBase).%New(..#TOOLNAME, ..#TOOLDESC)
    Set kb.TopK = $Select(topK<1:1, 1:topK)
    Return kb
}

ClassMethod GetVectorCount(tableName As %String) As %Integer [ Internal ]
{
    Set count = 0
    Try {
        Set sql = "SELECT COUNT(*) AS C FROM " _ tableName
        Set stmt = ##class(%SQL.Statement).%New()
        Set sc = stmt.%Prepare(sql)
        If $$$ISERR(sc) {
            Return 0
        }
        Set rs = stmt.%Execute()
        If rs.%Next() {
            Set count = +rs.%Get("C")
        }
    } Catch ex {
        Set count = 0
    }
    Return count
}

ClassMethod SeedDocuments() As %DynamicArray [ Internal ]
{
    Set docs = []

    // A1c
    Do docs.%Push(..Doc("A1c estimates average blood sugar over about 3 months. Higher A1c means blood sugar has been above target more often.", "ADA:a1c-overview", "a1c", "A1c overview"))
    Do docs.%Push(..Doc("Many adults with diabetes use a target near 7 percent, but personal goals may differ.", "ADA:a1c-targets", "a1c", "A1c targets"))

    // Lipids
    Do docs.%Push(..Doc("LDL is often called bad cholesterol. Lower LDL is usually linked to lower heart and stroke risk.", "AHA:ldl", "lipids", "LDL"))
    Do docs.%Push(..Doc("HDL and triglycerides add important context to risk and treatment decisions.", "AHA:hdl-triglycerides", "lipids", "HDL and triglycerides"))

    // CBC
    Do docs.%Push(..Doc("Hemoglobin carries oxygen. Low hemoglobin can cause fatigue or shortness of breath and may need further evaluation.", "Mayo:hemoglobin", "cbc", "Hemoglobin"))
    Do docs.%Push(..Doc("White blood cells help fight infection. Very high or very low counts can signal active illness or treatment effects.", "Cleveland:wbcs", "cbc", "WBC"))

    // CMP
    Do docs.%Push(..Doc("Creatinine is used to estimate kidney function. Rising creatinine over time can suggest worsening kidney filtration.", "NKF:creatinine", "cmp", "Creatinine"))
    Do docs.%Push(..Doc("Very low or very high potassium can affect heart rhythm and may require urgent follow-up.", "Medline:potassium", "cmp", "Potassium"))

    // General
    Do docs.%Push(..Doc("Ask your doctor what changed since last time, what target to aim for, and when to repeat testing.", "AHRQ:discussion", "general", "Questions"))

    Return docs
}

ClassMethod Doc(text As %String, source As %String, panel As %String, topic As %String) As %DynamicArray [ Internal ]
{
    Set metadata = {}
    Set metadata.source = source
    Set metadata.panel = panel
    Set metadata.topic = topic

    Set pair = []
    Do pair.%Push(text)
    Do pair.%Push(metadata)
    Return pair
}

ClassMethod NormalizePanel(panel As %String) As %String [ Internal ]
{
    Set p = $ZCONVERT($ZSTRIP(panel, "<>W"), "L")
    If p = "" {
        Return "general"
    }
    If (p [ "a1c") || (p [ "hba1c") {
        Return "a1c"
    }
    If (p [ "lipid") || (p [ "cholesterol") {
        Return "lipids"
    }
    If p [ "cbc" {
        Return "cbc"
    }
    If (p [ "cmp") || (p [ "metabolic") {
        Return "cmp"
    }
    Return "general"
}

}

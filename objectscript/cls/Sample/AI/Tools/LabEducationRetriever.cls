Include %occStatus

Class Sample.AI.Tools.LabEducationRetriever Extends %RegisteredObject
{

/// Returns grounded educational snippets for a panel/query using vector retrieval when available,
/// with deterministic local fallback if vector is unavailable or empty.
ClassMethod GetExplanationSnippets(panel As %String, query As %String = "", topK As %Integer = 3) As %DynamicObject
{
    Set normalizedPanel = ..NormalizePanel(panel)
    Set normalizedQuery = $ZSTRIP(query, "<>W")
    If normalizedQuery = "" {
        Set normalizedQuery = "Explain " _ normalizedPanel _ " results for a patient"
    }

    Set k = $Select(topK<1:1, 1:topK)
    Set result = {}
    Set result.panel = normalizedPanel
    Set result.query = normalizedQuery
    Set result.mode = "vector"
    Set result.status = "ok"

    Set vectorSnippets = ..TryVectorSearch(normalizedPanel, normalizedQuery, k)
    If ..CountSnippets(vectorSnippets) > 0 {
        Set result.snippets = vectorSnippets
        Return result
    }

    Set result.mode = "local-fallback"
    Set result.status = "fallback-used"
    Set result.snippets = ..BuildLocalFallback(normalizedPanel, normalizedQuery, k)

    If ..CountSnippets(result.snippets) = 0 {
        Set fallback = []
        Do fallback.%Push(..Snippet("general", "AHRQ", 0.10, "Ask your doctor what changed, why it changed, and what action to take now. Request a clear follow-up date."))
        Set result.snippets = fallback
        Set result.status = "fallback-default"
    }

    Return result
}

ClassMethod TryVectorSearch(panel As %String, query As %String, topK As %Integer) As %DynamicArray [ Internal ]
{
    Set snippets = []
    Set vectorAdapterClass = "Sample.AI.Tools.LabVectorAdapter"

    Try {
        Set customAdapter = ##class(%SYSTEM.Process).PrivateGlobalGet("LAB_VECTOR_ADAPTER_CLASS")
        If customAdapter '= "" {
            Set vectorAdapterClass = customAdapter
        }
    } Catch ex {
        // Keep default adapter when process private globals are unavailable.
    }

    If vectorAdapterClass = "" {
        Return snippets
    }

    If '##class(%Dictionary.ClassDefinition).%ExistsId(vectorAdapterClass) {
        Return snippets
    }

    Try {
        // Adapter must expose: SearchEducationalSnippets(panel, query, topK) -> dynamic array of snippet objects.
        Set adapterResult = $classmethod(vectorAdapterClass, "SearchEducationalSnippets", panel, query, topK)
        If $ISOBJECT(adapterResult) {
            Return adapterResult
        }
    } Catch ex {
        Return snippets
    }

    Return snippets
}

ClassMethod BuildLocalFallback(panel As %String, query As %String, topK As %Integer) As %DynamicArray [ Internal ]
{
    Set pool = ..LocalSnippetPool(panel)
    Set ranked = []

    For i=0:1:(pool.%Size()-1) {
        Set one = pool.%Get(i)
        Set score = ..LexicalScore(one.%Get("text"), query)
        Set one.score = score
        Do ranked.%Push(one)
    }

    Do ..SortByScoreDesc(.ranked)

    Set out = []
    Set cap = $Select(topK<1:1, 1:topK)
    Set kept = 0
    For i=0:1:(ranked.%Size()-1) {
        Quit:kept'<cap
        Set one = ranked.%Get(i)
        Do out.%Push(..Snippet(one.%Get("panel"), one.%Get("source"), one.%Get("score"), one.%Get("text")))
        Set kept = kept + 1
    }

    Return out
}

ClassMethod LocalSnippetPool(panel As %String) As %DynamicArray [ Internal ]
{
    Set snippets = []

    If panel = "a1c" {
        Do snippets.%Push(..Snippet("a1c", "ADA", 0.30, "A1c estimates average blood sugar over about 3 months. Higher A1c suggests blood sugar has been above target more often."))
        Do snippets.%Push(..Snippet("a1c", "ADA", 0.20, "Many adults with diabetes use a target near 7 percent, but personal targets vary by age and health conditions."))
        Do snippets.%Push(..Snippet("a1c", "CDC", 0.10, "Small changes in food, activity, and medicine adherence can improve A1c over time."))
    }

    If panel = "lipids" {
        Do snippets.%Push(..Snippet("lipids", "AHA", 0.30, "Higher LDL cholesterol can raise heart and stroke risk. Lowering LDL is often a major treatment goal."))
        Do snippets.%Push(..Snippet("lipids", "AHA", 0.20, "HDL and triglycerides add context to risk and can improve with diet, activity, and medication when needed."))
        Do snippets.%Push(..Snippet("lipids", "Mayo Clinic", 0.10, "Trends over time matter more than one isolated lipid value."))
    }

    If panel = "cbc" {
        Do snippets.%Push(..Snippet("cbc", "Mayo Clinic", 0.30, "Low hemoglobin can cause fatigue or shortness of breath and may need evaluation for bleeding, nutrition, or chronic disease."))
        Do snippets.%Push(..Snippet("cbc", "Cleveland Clinic", 0.20, "White blood cells help fight infection. Very high or low values can indicate infection, inflammation, or medication effects."))
        Do snippets.%Push(..Snippet("cbc", "AHRQ", 0.10, "Ask whether repeat testing is needed to confirm an abnormal CBC trend."))
    }

    If panel = "cmp" {
        Do snippets.%Push(..Snippet("cmp", "National Kidney Foundation", 0.30, "Creatinine helps estimate kidney function. Rising creatinine over time can suggest declining filtration."))
        Do snippets.%Push(..Snippet("cmp", "MedlinePlus", 0.20, "Potassium levels outside the normal range can affect heart rhythm and may require prompt follow-up."))
        Do snippets.%Push(..Snippet("cmp", "Mayo Clinic", 0.10, "CMP trends are often interpreted together with hydration status and medications."))
    }

    // Cross-panel educational baseline.
    Do snippets.%Push(..Snippet("general", "AHRQ", 0.05, "Ask what changed since your last test, what target to aim for, and when to repeat labs."))

    Return snippets
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

ClassMethod LexicalScore(text As %String, query As %String) As %Double [ Internal ]
{
    Set q = $ZCONVERT(query, "L")
    Set t = $ZCONVERT(text, "L")
    Set score = 0

    Set pieces = $L(q, " ")
    For i=1:1:pieces {
        Set token = $P(q, " ", i)
        If $L(token) < 3 {
            Continue
        }
        If t [ token {
            Set score = score + 1
        }
    }

    Return score
}

ClassMethod SortByScoreDesc(ByRef arr As %DynamicArray) [ Internal ]
{
    Set n = arr.%Size()
    If n < 2 Quit

    For i=0:1:(n-2) {
        For j=(i+1):1:(n-1) {
            Set a = arr.%Get(i)
            Set b = arr.%Get(j)
            Set sa = +a.%Get("score")
            Set sb = +b.%Get("score")
            If sb > sa {
                Set tmp = a
                Do arr.%Set(i, b)
                Do arr.%Set(j, tmp)
            }
        }
    }
}

ClassMethod Snippet(panel As %String, source As %String, score As %Double, text As %String) As %DynamicObject [ Internal ]
{
    Set o = {}
    Set o.panel = panel
    Set o.source = source
    Set o.score = score
    Set o.text = text
    Return o
}

ClassMethod CountSnippets(snippets As %DynamicArray) As %Integer [ Internal ]
{
    If '$ISOBJECT(snippets) {
        Return 0
    }
    Return snippets.%Size()
}

}

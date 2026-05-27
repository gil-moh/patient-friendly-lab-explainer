# Patient-Friendly Lab Explainer

Patient-facing lab explanation engine with deterministic output and grounded educational snippets.

## Current implementation status

Phase 1 has started with the grounding core:

- educational corpus schema
- seed educational corpus
- retrieval contract with pluggable vector provider
- deterministic local fallback snippets
- retrieval demo and relevance check harness

Phase 2 core is now implemented:

- panel-based FHIR observation retrieval
- lab normalization (value, unit, date, loinc)
- deterministic trend engine (latest vs prior, delta, direction)
- rule-based status classification (low/in-range/high)

## Retrieval contract

The retriever returns this stable shape:

- mode
- status
- query
- panel
- snippets: list of { text, source, score, panel }

This contract is consumed by later phases (trend engine and narrative composer).

## Quick start (phase 1)

1. Load and compile classes in IRIS.
2. Run:

```
Do ##class(Sample.AI.Examples.LabRetrieverDemo).Demo("a1c", "What does high A1c mean?", 3)
```

3. Run vector-backed retrieval demo:

```
Do ##class(Sample.AI.Examples.LabVectorDemo).Demo("a1c", "What does high A1c mean?", 3)
```

Expected when vector retrieval is active:

- mode=vector
- status=ok

4. Optional local relevance check in Python:

```
python scripts/eval_retrieval.py
```

## Quick start (phase 2)

Run deterministic synthetic trend demo (recommended first):

```
Do ##class(Sample.AI.Examples.LabTrendDemo).DemoSynthetic("a1c")
Do ##class(Sample.AI.Examples.LabTrendDemo).DemoSynthetic("lipids")
```

Run live FHIR trend demo:

```
Do ##class(Sample.AI.Examples.LabTrendDemo).Demo("demo-rich-003", "a1c")
Do ##class(Sample.AI.Examples.LabTrendDemo).Demo("demo-rich-003", "lipids")
```

Note: if live panel data is sparse in your current server state, the payload returns `no-data` per analyte while preserving deterministic output shape.

## Quick start (phase 3)

Run deterministic patient-facing narrative:

```
Do ##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoSynthetic("a1c")
```

Write clean narrative output directly to file:

```
Do ##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("demo-rich-003", "a1c", "/tmp/patient-lab-a1c.txt", 1)
```

## Toolset integration

Tool classes and toolset are now available:

- `Sample.AI.Tools.PatientLabTool`
- `Sample.AI.ToolSet.PatientLabTool`

Main entry methods:

- `ExplainLabPanel(patientId, panel)`
- `ExplainLabPanelSynthetic(panel)`

## Quality and artifacts

Run synthetic contract checks:

```
cmd /c scripts\run_quality_checks.cmd
```

Generate demo artifact files in one command:

```
cmd /c scripts\run_all_demos.cmd
```

Generated files are written to `demo_outputs/`.

# Patient-Friendly Lab Explainer

An AI agent built on InterSystems IRIS for Health that converts raw lab results into plain-language patient explanations. It retrieves FHIR observations, identifies trends, and generates grounded narratives using Vector Search over a trusted educational corpus — so patients can understand what their labs mean, how they changed, and what questions to ask their doctor.

Supports A1c, lipid panel, CBC, and CMP. Works with or without live FHIR patient data (synthetic demos included).

## Team

- Gil Tavassy — [Developer Community profile](https://community.intersystems.com/user/gil-tavassy) · [LinkedIn](https://www.linkedin.com/in/gil-tavassy-5703b311b)

Submission mode: solo project.

## Demo outputs

Sample narratives generated against a live FHIR server are in [`demo_outputs/`](demo_outputs/).

Two test patients are included — a diabetic patient (`lab-test-001`) and an alcoholic liver disease / STD case (`alco-test-001`) — run across A1c, lipid panel, CBC, and CMP.

## Prerequisites

- **Docker Desktop** (Windows / Mac) or Docker Engine (Linux)
- **InterSystems IRIS for Health AI Hub EAP image** — the AI Hub is baked into this image; no separate install is needed.
  1. Register / log in at https://evaluation.intersystems.com/Eval/early-access/AIHub and select the **AI Hub** program.
  2. Download **two files**:
     - `irishealth-community-2026.2.0AI.162.0-docker.tar.gz` (x64) — or the `arm64` variant for Mac M-series
     - `iris-container-x64.key` (or `iris-container-arm64.key` for ARM64)
  3. Load and tag the image (one-time step per machine):
     ```
     docker image load -i irishealth-community-2026.2.0AI.162.0-docker.tar.gz
     docker tag docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.2.0AI.162.0 irishealth-community:2026.2.0AI.162.0
     ```

## Quick start

1. Clone this repository.
2. Copy your `iris-container-x64.key` into the `keys/` folder at the repo root.
3. Open `.env` and set `FHIR_BASE_URL` to your FHIR server's address. The default (`http://host.docker.internal:52773/fhir/r4`) points to the standard IRIS web port on your host machine — no change needed if that is where your server runs.
4. Build and start:
   ```
   docker compose build
   docker compose up -d
   ```
5. Wait ~60 seconds for IRIS to become healthy, then run a synthetic demo (no FHIR patient data needed):
   ```
   docker exec patient-friendly-lab-explainer-iris-1 bash -c \
     "printf 'Do ##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoSynthetic(\"a1c\")\nHalt\n' | iris session IRIS -U USER 2>&1 | grep -Ev '^(USER>|Node:)'"
   ```

## FHIR server

The application connects to any FHIR R4 endpoint. Two options:

**Option A — Built-in IRIS for Health FHIR server (standard Community image)**

The standard `intersystemsdc/irishealth-community:latest` image ships with a pre-configured FHIR server at `http://localhost:52773/fhir/r4`. To use it instead of the AI Hub image, override the build arg:

```
docker compose build --build-arg IMAGE=intersystemsdc/irishealth-community:latest
```

Note: this image does not include AI Hub, so vector retrieval falls back to local lexical search.

**Option B — Any external FHIR R4 server**

Set environment variables before `docker compose up`:

```
FHIR_BASE_URL=https://your-fhir-server/fhir/r4
FHIR_BEARER_TOKEN=your-token
```

The synthetic demos (`DemoSynthetic`) work without any FHIR server — no patient data is needed to evaluate the explanation engine.

**Important — connecting to a FHIR server on your host machine:**

Inside Docker, `localhost` resolves to the container itself, not your host. If your FHIR server is running on the host machine, use:

- **Mac / Windows (Docker Desktop):** `host.docker.internal`
  ```
  FHIR_BASE_URL=http://host.docker.internal:52773/fhir/r4
  ```
The `docker-compose.yml` includes `extra_hosts: host.docker.internal:host-gateway` so `host.docker.internal` resolves correctly on Linux Docker Engine too — no manual IP lookup needed.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `FHIR_BASE_URL` | `http://host.docker.internal:52773/fhir/r4` | FHIR R4 endpoint for live patient queries |
| `FHIR_BASIC_USER` | `_SYSTEM` | Basic auth username |
| `FHIR_BASIC_PASS` | `SYS` | Basic auth password |
| `FHIR_BEARER_TOKEN` | _(none)_ | Bearer token (alternative to basic auth) |

These values are read from `.env` at startup — edit that file to point at your FHIR server before running `docker compose up`.

## How it works

The engine runs three stages:

**1. FHIR retrieval** (`Sample.AI.Tools.LabReadOnly`)
Queries a FHIR R4 server for a patient's Observation and DiagnosticReport resources for the requested panel. Normalizes values, units, dates, and LOINC codes into a stable shape.

**2. Trend analysis** (`Sample.AI.Tools.LabTrendEngine`)
Compares the latest and prior result for each analyte. Computes delta, direction, and rule-based status (low / in-range / high) using standard reference ranges.

**3. Narrative composition** (`Sample.AI.Tools.PatientLabExplainer`)
Assembles a patient-facing narrative with:
- current results and status
- trend summary
- plain-language explanation grounded in Vector Search snippets from the educational corpus
- context from the patient's medical record (conditions, medications, allergies, family history)
- lifestyle options
- suggested questions for the doctor
- recommended next step

**Vector Search grounding** (`Sample.AI.Tools.LabVectorAdapter`)
Uses `%AI.RAG.Embedding.FastEmbed` and `%AI.RAG.VectorStore.IRIS` to retrieve the most relevant educational snippets for each analyte from a curated corpus sourced from ADA, AHA, Mayo Clinic, Cleveland Clinic, and AHRQ guidelines. Falls back to local lexical search when Vector Search is unavailable.

## Toolset integration

The engine is packaged as an AI Hub Tool and ToolSet for direct use by `%AI.Agent`:

- `Sample.AI.Tools.PatientLabTool` — extends `%AI.Tool`
- `Sample.AI.ToolSet.PatientLabTool` — extends `%AI.ToolSet`

Entry methods:

```
Do ##class(Sample.AI.Tools.PatientLabTool).ExplainLabPanel(patientId, panel)
Do ##class(Sample.AI.Tools.PatientLabTool).ExplainLabPanelSynthetic(panel)
```

## All demo commands

Wrapper to run any ObjectScript command cleanly (no IRIS session prompts):

```bash
docker exec patient-friendly-lab-explainer-iris-1 bash -c \
  "printf '<command>\nHalt\n' | iris session IRIS -U USER 2>&1 | grep -Ev '^(USER>|Node:)'"
```

Available commands:

```objectscript
// Patient-facing narratives (synthetic data, no FHIR server needed)
Do ##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoSynthetic("a1c")
Do ##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoSynthetic("lipids")

// Lab trend engine (synthetic)
Do ##class(Sample.AI.Examples.LabTrendDemo).DemoSynthetic("a1c")
Do ##class(Sample.AI.Examples.LabTrendDemo).DemoSynthetic("lipids")

// Vector retrieval
Do ##class(Sample.AI.Examples.LabVectorDemo).Demo("a1c", "What does high A1c mean?", 3)
Do ##class(Sample.AI.Examples.LabRetrieverDemo).Demo("a1c", "What does high A1c mean?", 3)

// Live FHIR demos (requires a FHIR server with at least one patient loaded)
// Replace <your-patient-id> with the FHIR logical ID of a patient in your server
Do ##class(Sample.AI.Examples.LabTrendDemo).Demo("<your-patient-id>", "a1c")
Do ##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("<your-patient-id>", "a1c", "/home/irisowner/patient-lab-a1c.txt", 0)
// Then copy out: docker cp patient-friendly-lab-explainer-iris-1:/home/irisowner/patient-lab-a1c.txt .
```

## Quality checks

Verify synthetic contract output:

```
docker exec patient-friendly-lab-explainer-iris-1 bash -c \
  "printf 'Do ##class(Sample.AI.Examples.PatientLabQualityChecks).RunAll()\nHalt\n' | iris session IRIS -U USER"
```

Local educational corpus relevance check (Python, no IRIS needed):

```
python scripts/eval_retrieval.py
```

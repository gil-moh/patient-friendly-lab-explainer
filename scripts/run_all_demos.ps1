$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'demo_outputs'
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

# Generates demo output files from a live FHIR server.
#
# Before running:
# 1. Set $patientId below to the FHIR logical ID of a patient in your server.
# 2. Ensure FHIR_BASE_URL is set correctly when running docker compose.
#    Inside Docker, localhost = the container, not the host. Use:
#      - Mac/Windows: host.docker.internal  e.g. http://host.docker.internal:52773/fhir/r4
#      - Linux:       172.17.0.1            e.g. http://172.17.0.1:52773/fhir/r4
#    Set via: FHIR_BASE_URL=http://host.docker.internal:PORT/fhir/r4 docker compose up -d

$patientId = "REPLACE_WITH_YOUR_PATIENT_ID"

$macro = @"
zn "USER"
set sc1=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("$patientId","a1c","/tmp/patient-lab-a1c.txt",0)
write !,"A1C=",`$system.Status.GetOneErrorText(sc1),!
set sc2=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("$patientId","lipids","/tmp/patient-lab-lipids.txt",0)
write !,"LIPIDS=",`$system.Status.GetOneErrorText(sc2),!
set sc3=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("$patientId","cmp","/tmp/patient-lab-cmp.txt",0)
write !,"CMP=",`$system.Status.GetOneErrorText(sc3),!
halt
"@

$macroFile = Join-Path $env:TEMP 'patient_lab_explainer_run_all.mac'
Set-Content -Path $macroFile -Value $macro -Encoding ascii
$container = "patient-friendly-lab-explainer-iris-1"
Get-Content -Raw $macroFile | docker exec -i $container iris session IRIS

docker cp "${container}:/tmp/patient-lab-a1c.txt" (Join-Path $outDir 'patient-lab-a1c.txt') | Out-Null
docker cp "${container}:/tmp/patient-lab-lipids.txt" (Join-Path $outDir 'patient-lab-lipids.txt') | Out-Null
docker cp "${container}:/tmp/patient-lab-cmp.txt" (Join-Path $outDir 'patient-lab-cmp.txt') | Out-Null

Write-Host "Generated artifacts:"
Write-Host "- $outDir\patient-lab-a1c.txt"
Write-Host "- $outDir\patient-lab-lipids.txt"
Write-Host "- $outDir\patient-lab-cmp.txt"

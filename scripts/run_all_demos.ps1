$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'demo_outputs'
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

# Generates demo output files using synthetic patient data (no FHIR server needed).
# The last argument (1) enables synthetic mode — no patient ID or FHIR connection required.
# To run against a real patient, change the last argument to 0 and replace "synthetic"
# with your patient's FHIR ID. Also set FHIR_BASE_URL — see README for Docker networking.
$macro = @'
zn "USER"
set sc1=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("synthetic","a1c","/tmp/patient-lab-a1c.txt",1)
write !,"A1C=",$system.Status.GetOneErrorText(sc1),!
set sc2=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("synthetic","lipids","/tmp/patient-lab-lipids.txt",1)
write !,"LIPIDS=",$system.Status.GetOneErrorText(sc2),!
set sc3=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("synthetic","cmp","/tmp/patient-lab-cmp.txt",1)
write !,"CMP=",$system.Status.GetOneErrorText(sc3),!
halt
'@

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

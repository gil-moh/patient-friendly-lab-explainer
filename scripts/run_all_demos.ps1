$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'demo_outputs'
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

# Generates demo output files using synthetic patient data (no FHIR server needed).
# To run against a real patient, replace DemoSynthetic with DemoToFile and supply
# a patient ID, e.g.: DemoToFile("your-patient-id","a1c","/tmp/patient-lab-a1c.txt",1)
# Also set FHIR_BASE_URL before docker compose up — see README for Docker networking notes.
$macro = @'
zn "USER"
set sc1=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoSynthetic("a1c")
write !,"A1C=",$system.Status.GetOneErrorText($$$OK),!
set sc2=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoSynthetic("lipids")
write !,"LIPIDS=",$system.Status.GetOneErrorText($$$OK),!
set sc3=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoSynthetic("cmp")
write !,"CMP=",$system.Status.GetOneErrorText($$$OK),!
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

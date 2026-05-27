param(
    [string]$MacroPath = "C:\Projects\FHIR\tmp_validation\macros\tmp_show_various_outputs.mac",
    [string]$Container = "iris-ai-hub-162"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $MacroPath)) {
    throw "Macro file not found: $MacroPath"
}

$raw = (Get-Content -Raw $MacroPath | docker exec -i $Container iris session IRIS | Out-String)
$lines = $raw -split "`r?`n"

$filtered = $lines | Where-Object {
    ($_ -notmatch '^\s*Node:\s') -and
    ($_ -notmatch '^\s*USER>\s*$')
}

# Keep readable section spacing while avoiding huge blank blocks.
$cleaned = [System.Collections.Generic.List[string]]::new()
$blankCount = 0
foreach ($line in $filtered) {
    if ($line -match '^\s*$') {
        $blankCount++
        if ($blankCount -le 2) {
            [void]$cleaned.Add("")
        }
    } else {
        $blankCount = 0
        [void]$cleaned.Add($line)
    }
}

($cleaned -join "`n").Trim() | Write-Output

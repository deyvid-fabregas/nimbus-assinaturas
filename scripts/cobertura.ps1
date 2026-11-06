param([string]$Org = 'nimbus-org')
Set-Location (Split-Path $PSScriptRoot -Parent)
sf project deploy start -o $Org --source-dir force-app\main\default\classes --wait 30 --json 2>$null | Out-File $env:TEMP\d.json -Encoding utf8
$d = (Get-Content $env:TEMP\d.json -Raw -Encoding utf8 | ConvertFrom-Json).result
"deploy: $($d.status)"
$d.details.componentFailures | ForEach-Object { "$($_.fullName): $($_.problem)" }
sf apex run test -o $Org --test-level RunLocalTests --code-coverage --result-format json --wait 30 2>$null | Out-File $env:TEMP\t.json -Encoding utf8
$t = (Get-Content $env:TEMP\t.json -Raw -Encoding utf8 | ConvertFrom-Json).result
"ran=$($t.summary.testsRan) pass=$($t.summary.passing) fail=$($t.summary.failing) cov=$($t.summary.testRunCoverage)"
$t.tests | Where-Object Outcome -ne 'Pass' | ForEach-Object { "FAIL $($_.FullName): $($_.Message)" }
sf data query --use-tooling-api -q "SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate" -o $Org --json 2>$null | Out-File $env:TEMP\c.json -Encoding utf8
$rows = (Get-Content $env:TEMP\c.json -Raw -Encoding utf8 | ConvertFrom-Json).result.records | ForEach-Object {
    $tot = $_.NumLinesCovered + $_.NumLinesUncovered
    [pscustomobject]@{ N = $_.ApexClassOrTrigger.Name; C = $_.NumLinesCovered; T = $tot; P = $(if ($tot) { [math]::Round(100 * $_.NumLinesCovered / $tot) } else { 100 }) }
} | Sort-Object P
"abaixo de 90: " + (($rows | Where-Object P -lt 90 | ForEach-Object { "$($_.N)=$($_.P)%" }) -join '; ')
"total=$($rows.Count) ok=$(($rows | Where-Object P -ge 90).Count)"
$rows | ForEach-Object { "| $($_.N) | $($_.C)/$($_.T) | $($_.P)% |" } | Out-File $env:TEMP\rows.txt -Encoding utf8

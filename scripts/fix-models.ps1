# Makes Studio-saved XML models (models/*.rbxmx) readable by Rojo.
# Studio now serializes the Tags property as a SharedString; Rojo (7.5.1) only understands the classic
# BinaryString form, so this inlines each Tags entry from the file's SharedStrings table. Idempotent: a file
# that has already been fixed has no SharedString Tags left and is left untouched.
#
# Export recipe: Explorer > right-click the folder > Save / Export > Save to File > models\<Name>.rbxmx,
# then run this script (check.ps1 runs it first anyway).

param(
    [string[]]$Paths = @(Get-ChildItem -Path (Join-Path $PSScriptRoot "..\models\*.rbxmx") | ForEach-Object { $_.FullName })
)

$ErrorActionPreference = "Stop"
$tagsPattern = '<SharedString name="Tags">([^<]*)</SharedString>'
$tablePattern = '<SharedString md5="([^"]+)">([^<]*)</SharedString>'
# Studio also writes a fifth PhysicalProperties field (acoustics) that Rojo's XML reader rejects; nothing here uses it.
$acousticPattern = '\s*<AcousticAbsorption>[^<]*</AcousticAbsorption>'

foreach ($path in $Paths) {
    $xml = [System.IO.File]::ReadAllText($path)
    if ($xml -notmatch $tagsPattern -and $xml -notmatch $acousticPattern) {
        Write-Host "fix-models: $([System.IO.Path]::GetFileName($path)) already clean"
        continue
    }
    $acoustic = [regex]::Matches($xml, $acousticPattern).Count
    $xml = [regex]::Replace($xml, $acousticPattern, "")
    $table = @{}
    foreach ($m in [regex]::Matches($xml, $tablePattern)) {
        $table[$m.Groups[1].Value] = $m.Groups[2].Value.Trim()
    }
    $count = 0
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $script:count++
        $hash = $m.Groups[1].Value.Trim()
        $content = if ($table.ContainsKey($hash)) { $table[$hash] } else { "" }
        return "<BinaryString name=`"Tags`">$content</BinaryString>"
    }
    $fixed = [regex]::Replace($xml, $tagsPattern, $evaluator)
    [System.IO.File]::WriteAllText($path, $fixed, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "fix-models: $([System.IO.Path]::GetFileName($path)) rewrote $count Tags properties, dropped $acoustic AcousticAbsorption fields"
}

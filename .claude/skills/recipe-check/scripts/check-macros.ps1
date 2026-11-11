<#
  Mechanical checks for one recipe file. The skill runs this so the maths and
  word searches come out the same every time; Claude makes the judgment calls.

  Example:
    powershell -NoProfile -File check-macros.ps1 -Path recipes\greek-chicken-sheet-pan.md
#>
param(
  [Parameter(Mandatory = $true)][string]$Path,
  [int]$MinKcal = 300,
  [int]$MaxKcal = 500,
  [int]$MinProtein = 50,
  # Comma-separated, because "powershell -File" passes a list as one string.
  [string]$Banned = 'yogurt,yoghurt,cucumber,zucchini,courgette,tzatziki,raita'
)

function Mark([bool]$ok) { if ($ok) { 'PASS' } else { 'FAIL' } }

$name = [IO.Path]::GetFileNameWithoutExtension($Path)
$text = Get-Content -Raw -LiteralPath $Path
"recipe: $name"

# 1-2. Calories and protein, read from the "Estimated:" line.
$pattern = 'Estimated:\s*([\d.]+)\s*kcal\s*\|\s*([\d.]+)\s*g protein\s*\|\s*([\d.]+)\s*g carbs\s*\|\s*([\d.]+)\s*g fat'
$m = [regex]::Match($text, $pattern)
if ($m.Success) {
  $kcal    = [double]$m.Groups[1].Value
  $protein = [double]$m.Groups[2].Value
  $carbs   = [double]$m.Groups[3].Value
  $fat     = [double]$m.Groups[4].Value

  "kcal: $kcal $(Mark ($kcal -ge $MinKcal -and $kcal -le $MaxKcal)) (target $MinKcal-$MaxKcal)"
  "protein: $protein g $(Mark ($protein -ge $MinProtein)) (target $MinProtein g or more)"

  # 4. Do the macros add up? 4 kcal per g protein and carbs, 9 per g fat.
  $fromMacros = 4 * $protein + 4 * $carbs + 9 * $fat
  $diff = [math]::Round(100 * [math]::Abs($kcal - $fromMacros) / $kcal, 1)
  "macros add up: $(Mark ($diff -le 10)) (stated $kcal kcal, macros give $fromMacros kcal, $diff% apart)"
} else {
  'kcal: FAIL (no "Estimated: ... kcal | ... g protein | ... g carbs | ... g fat" line found)'
  'protein: FAIL (see above)'
  'macros add up: FAIL (see above)'
}

# 3. Banned ingredients anywhere in the file, with line numbers.
$hits = foreach ($word in ($Banned -split ',')) {
  Select-String -LiteralPath $Path -Pattern $word.Trim() -SimpleMatch |
    ForEach-Object { "line $($_.LineNumber): '$($word.Trim())' in: $($_.Line.Trim())" }
}
if ($hits) { 'banned items: FAIL'; $hits | ForEach-Object { "  $_" } }
else       { 'banned items: PASS' }

# 5. Matching editable-servings page.
$html = Join-Path (Split-Path -Parent $Path) "$name.html"
"html page: $(Mark (Test-Path -LiteralPath $html))"

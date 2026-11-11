<#
  Checks the editable-servings page for one recipe:
    1. its RECIPE data matches the Markdown recipe (servings and macros),
    2. its code matches the template page (recipes/beef-and-broccoli-stir-fry.html),
    3. it works in a real browser: page-test.js clicks through servings, cooking
       mode, timers and keyboard shortcuts in headless Chrome or Edge.

  Read-only for the project. The browser runs on a copy in a temporary folder,
  which is deleted afterwards.

  Example:
    powershell -NoProfile -File check-page.ps1 -Path recipes\greek-chicken-sheet-pan.md
#>
param(
  [Parameter(Mandatory = $true)][string]$Path,
  [string]$Template = 'recipes\beef-and-broccoli-stir-fry.html',
  [int]$TimeoutSeconds = 60
)

function Mark([bool]$ok) { if ($ok) { 'PASS' } else { 'FAIL' } }

$dir  = Split-Path -Parent $Path
$name = [IO.Path]::GetFileNameWithoutExtension($Path)
$md   = Join-Path $dir "$name.md"
$html = Join-Path $dir "$name.html"
"page: $name.html"

if (-not (Test-Path -LiteralPath $html)) { 'page exists: FAIL (no .html file, nothing else to test)'; exit }
$page = Get-Content -Raw -Encoding UTF8 -LiteralPath $html

# 1. Page data matches the Markdown recipe.
if (Test-Path -LiteralPath $md) {
  $mdText = Get-Content -Raw -Encoding UTF8 -LiteralPath $md
  $mdM = [regex]::Match($mdText, 'Estimated:\s*([\d.]+)\s*kcal\s*\|\s*([\d.]+)\s*g protein\s*\|\s*([\d.]+)\s*g carbs\s*\|\s*([\d.]+)\s*g fat')
  $pgM = [regex]::Match($page, 'macros:\s*\{\s*kcal:\s*([\d.]+),\s*protein:\s*([\d.]+),\s*carbs:\s*([\d.]+),\s*fat:\s*([\d.]+)')
  if ($mdM.Success -and $pgM.Success) {
    $labels = 'kcal', 'protein', 'carbs', 'fat'
    $diffs = foreach ($i in 1..4) {
      if ([double]$mdM.Groups[$i].Value -ne [double]$pgM.Groups[$i].Value) {
        "$($labels[$i-1]) $($mdM.Groups[$i].Value) in .md vs $($pgM.Groups[$i].Value) in page"
      }
    }
    if ($diffs) { "macros match .md: FAIL ($($diffs -join '; '))" } else { 'macros match .md: PASS' }
  } else {
    "macros match .md: FAIL (could not read macros from $(if (-not $mdM.Success) { 'the .md Estimated line' } else { 'the page RECIPE.macros' }))"
  }
  $mdS = [regex]::Match($mdText, '(?m)^Servings:\s*(\d+)')
  $pgS = [regex]::Match($page, 'baseServings:\s*(\d+)')
  if ($mdS.Success -and $pgS.Success) {
    "servings match .md: $(Mark ($mdS.Groups[1].Value -eq $pgS.Groups[1].Value)) ($($mdS.Groups[1].Value) in .md, $($pgS.Groups[1].Value) in page)"
  } else {
    'servings match .md: FAIL (could not read servings from both files)'
  }
} else {
  'macros match .md: FAIL (no .md file to compare with)'
}

# 2. Same page code as the template, apart from the RECIPE object and <title>.
function Strip([string]$text) {
  $text = $text -replace '\r\n', "`n"
  $text = [regex]::Replace($text, '(?ms)^const RECIPE = \{.*?^\};', '<<RECIPE>>')
  [regex]::Replace($text, '<title>.*?</title>', '<title>')
}
if ((Resolve-Path -LiteralPath $html).Path -eq (Resolve-Path -LiteralPath $Template -ErrorAction SilentlyContinue).Path) {
  'template: PASS (this page is the template)'
} elseif (-not (Test-Path -LiteralPath $Template)) {
  "template: FAIL (template $Template not found)"
} else {
  $a = (Strip (Get-Content -Raw -Encoding UTF8 -LiteralPath $Template)) -split "`n"
  $b = (Strip $page) -split "`n"
  $delta = Compare-Object $a $b
  if (-not $delta) {
    'template: PASS (same code as the template)'
  } else {
    "template: FAIL ($(@($delta).Count) lines differ from $([IO.Path]::GetFileName($Template)) outside the recipe data; the page may be an older copy or edited by hand)"
    $delta | Select-Object -First 6 | ForEach-Object {
      $side = if ($_.SideIndicator -eq '<=') { 'template only' } else { 'page only' }
      $line = $_.InputObject.Trim()
      if ($line.Length -gt 100) { $line = $line.Substring(0, 100) + '...' }
      "  $side`: $line"
    }
  }
}

# 3. Browser test.
$browser = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $browser) { 'browser test: SKIPPED (Chrome or Edge not found)'; exit }

$work = Join-Path ([IO.Path]::GetTempPath()) ("recipe-check-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $testJs = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'page-test.js')
  $catcher = '<script>window.__pageErrors=[];addEventListener("error",function(e){__pageErrors.push(e.message)});</script>'
  $copy = [regex]::Replace($page, '</title>', '</title>' + $catcher, 1)
  $copy += "`n<script>`n$testJs`n</script>`n"
  $testPage = Join-Path $work "$name.html"
  [IO.File]::WriteAllText($testPage, $copy, (New-Object Text.UTF8Encoding $false))

  $outFile = Join-Path $work 'dom.html'
  $errFile = Join-Path $work 'stderr.txt'
  $url = 'file:///' + ($testPage -replace '\\', '/')
  $argList = @('--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    "--user-data-dir=`"$(Join-Path $work 'profile')`"", '--virtual-time-budget=3000', '--dump-dom', "`"$url`"")
  $proc = Start-Process -FilePath $browser -ArgumentList $argList -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile
  if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch {}
    "browser test: FAIL (browser did not finish within $TimeoutSeconds seconds)"
    exit
  }

  $dom = if (Test-Path $outFile) { Get-Content -Raw -Encoding UTF8 -LiteralPath $outFile } else { '' }
  # The results element is appended last, so take the last match.
  $m = [regex]::Match([string]$dom, '(?s)<pre id="TEST-RESULTS">(.*?)</pre>', 'RightToLeft')
  if (-not $m.Success) {
    'browser test: FAIL (the test never finished; the page script probably stopped with an error before it)'
    exit
  }
  $lines = [Net.WebUtility]::HtmlDecode($m.Groups[1].Value) -split '\r?\n' | Where-Object { $_.Trim() }
  $fails = @($lines | Where-Object { $_ -like 'FAIL*' }).Count
  $passes = @($lines | Where-Object { $_ -like 'PASS*' }).Count
  "browser test: $(Mark ($fails -eq 0)) ($passes passed, $fails failed, in $([IO.Path]::GetFileNameWithoutExtension($browser)))"
  $lines | ForEach-Object { "  $_" }
} finally {
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

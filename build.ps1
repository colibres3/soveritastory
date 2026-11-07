<#
.SYNOPSIS
    Builds the static blog website from markdown posts and templates.
    Fully cross-platform PowerShell implementation with zero external dependencies.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "config.md",
    [string]$PostsDir = "posts",
    [string]$SiteDir = "site"
)

$ErrorActionPreference = "Stop"

function Convert-MarkdownToHtml {
    param([string]$Markdown)

    $lines = $Markdown -split "`r?`n"
    $html = [System.Collections.Generic.List[string]]::new()
    
    $inCodeBlock = $false
    $codeLang = ""
    $codeLines = [System.Collections.Generic.List[string]]::new()
    $inUl = $false
    $inOl = $false
    $inBlockquote = $false
    $blockquoteLines = [System.Collections.Generic.List[string]]::new()
    $cbIndex = 1

    function Format-Inline {
        param([string]$text)
        # HTML escape first for safety (except where we generate html)
        $text = [System.Net.WebUtility]::HtmlEncode($text)
        
        # Inline code `code`
        $text = [regex]::Replace($text, '`([^`]+)`', '<code>$1</code>')
        
        # Images ![alt](url)
        $text = [regex]::Replace($text, '!\[([^\]]*)\]\(([^)]+)\)', '<img src="$2" alt="$1" />')
        
        # Links [text](url)
        $text = [regex]::Replace($text, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')
        
        # Bold **text** or __text__
        $text = [regex]::Replace($text, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
        $text = [regex]::Replace($text, '__([^_]+)__', '<strong>$1</strong>')
        
        # Italic *text* or _text_
        $text = [regex]::Replace($text, '(?<!\*)\*([^*]+)\*(?!\*)', '<em>$1</em>')
        $text = [regex]::Replace($text, '(?<!_)_([^_]+)_(?!_)', '<em>$1</em>')
        
        return $text
    }

    function Highlight-PythonLine {
        param([string]$rawLine, [int]$lineNum, [string]$cbId)
        $lineEscaped = [System.Net.WebUtility]::HtmlEncode($rawLine)
        
        # Highlight keywords
        $lineEscaped = [regex]::Replace($lineEscaped, '\b(def|class|lambda|import|from|as|global|nonlocal|pass)\b', '<span class="kw">$1</span>')
        # Control flow
        $lineEscaped = [regex]::Replace($lineEscaped, '\b(return|if|elif|else|for|while|break|continue|try|except|finally|with|yield|raise)\b', '<span class="cf">$1</span>')
        # Built-in constants
        $lineEscaped = [regex]::Replace($lineEscaped, '\b(True|False|None)\b', '<span class="kw">$1</span>')
        # Numbers
        $lineEscaped = [regex]::Replace($lineEscaped, '\b(\d+)\b', '<span class="dv">$1</span>')
        # Strings
        $lineEscaped = [regex]::Replace($lineEscaped, '(&quot;[^&]*&quot;|&#39;[^&]*&#39;)', '<span class="st">$1</span>')

        return "<a class=`"sourceLine`" id=`"${cbId}-${lineNum}`" title=`"${lineNum}`">${lineEscaped}</a>"
    }

    foreach ($line in $lines) {
        # Check code fence
        if ($line -match '^```(\w*)\s*$') {
            if (-not $inCodeBlock) {
                # Close list / blockquote if open
                if ($inUl) { $html.Add("</ul>"); $inUl = $false }
                if ($inOl) { $html.Add("</ol>"); $inOl = $false }
                if ($inBlockquote) {
                    $bqContent = Format-Inline ($blockquoteLines -join " ")
                    $html.Add("<blockquote><p>$bqContent</p></blockquote>")
                    $blockquoteLines.Clear()
                    $inBlockquote = $false
                }
                $inCodeBlock = $true
                $codeLang = $matches[1]
                $codeLines.Clear()
                continue
            } else {
                # End code block
                $cbId = "cb$cbIndex"
                $cbIndex++
                $langClass = if ($codeLang) { " $codeLang" } else { "" }
                $html.Add("<div class=`"sourceCode`" id=`"$cbId`"><pre class=`"sourceCode$langClass`"><code class=`"sourceCode$langClass`">")
                
                $lineNum = 1
                foreach ($cLine in $codeLines) {
                    if ($codeLang -eq 'python') {
                        $html.Add((Highlight-PythonLine -rawLine $cLine -lineNum $lineNum -cbId $cbId))
                    } else {
                        $cEsc = [System.Net.WebUtility]::HtmlEncode($cLine)
                        $html.Add("<a class=`"sourceLine`" id=`"${cbId}-${lineNum}`" title=`"${lineNum}`">${cEsc}</a>")
                    }
                    $lineNum++
                }
                $html.Add("</code></pre></div>")
                $inCodeBlock = $false
                $codeLang = ""
                $codeLines.Clear()
                continue
            }
        }

        if ($inCodeBlock) {
            $codeLines.Add($line)
            continue
        }

        # Check blockquote
        if ($line -match '^>\s?(.*)$') {
            if ($inUl) { $html.Add("</ul>"); $inUl = $false }
            if ($inOl) { $html.Add("</ol>"); $inOl = $false }
            $inBlockquote = $true
            $blockquoteLines.Add($matches[1])
            continue
        } elseif ($inBlockquote) {
            $bqContent = Format-Inline ($blockquoteLines -join " ")
            $html.Add("<blockquote><p>$bqContent</p></blockquote>")
            $blockquoteLines.Clear()
            $inBlockquote = $false
        }

        # Check lists
        if ($line -match '^\s*[-*+]\s+(.*)$') {
            if (-not $inUl) {
                if ($inOl) { $html.Add("</ol>"); $inOl = $false }
                $html.Add("<ul>")
                $inUl = $true
            }
            $html.Add("  <li>" + (Format-Inline $matches[1]) + "</li>")
            continue
        } elseif ($inUl -and $line.Trim() -ne '') {
            $html.Add("</ul>")
            $inUl = $false
        }

        if ($line -match '^\s*\d+\.\s+(.*)$') {
            if (-not $inOl) {
                if ($inUl) { $html.Add("</ul>"); $inUl = $false }
                $html.Add("<ol>")
                $inOl = $true
            }
            $html.Add("  <li>" + (Format-Inline $matches[1]) + "</li>")
            continue
        } elseif ($inOl -and $line.Trim() -ne '') {
            $html.Add("</ol>")
            $inOl = $false
        }

        # Empty line
        if ($line.Trim() -eq '') {
            if ($inUl) { $html.Add("</ul>"); $inUl = $false }
            if ($inOl) { $html.Add("</ol>"); $inOl = $false }
            continue
        }

        # Horizontal rule
        if ($line -match '^(\-{3,}|\*{3,}|_{3,})$') {
            $html.Add("<hr>")
            continue
        }

        # Headings
        if ($line -match '^(#{1,6})\s+(.*)$') {
            $level = $matches[1].Length
            $htext = Format-Inline $matches[2]
            $slug = ($matches[2].ToLower() -replace '[^\w\s-]', '') -replace '\s+', '-'
            $html.Add("<h$level id=`"$slug`">$htext</h$level>")
            continue
        }

        # Normal paragraph
        $pText = Format-Inline $line
        $html.Add("<p>$pText</p>")
    }

    if ($inUl) { $html.Add("</ul>") }
    if ($inOl) { $html.Add("</ol>") }
    if ($inBlockquote) {
        $bqContent = Format-Inline ($blockquoteLines -join " ")
        $html.Add("<blockquote><p>$bqContent</p></blockquote>")
    }

    return ($html -join "`n")
}

function Get-Metadata {
    param([string]$FilePath, [string]$PostFilename = $null)

    $meta = @{}
    if ($PostFilename) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($PostFilename)
        $meta["filename"] = "$base.html"
    }

    $rawLines = [System.IO.File]::ReadAllLines($FilePath, [System.Text.Encoding]::UTF8)
    $bodyLines = [System.Collections.Generic.List[string]]::new()
    $inHeader = $true

    foreach ($line in $rawLines) {
        if ($inHeader -and $line -match '^\s*\[([^\]]+)\](?::\s*<>\s*|\s*)\(([^)]*)\)') {
            $key = $matches[1].Trim().ToLower()
            $val = $matches[2].Trim()

            if ($key -in @('category', 'categories')) {
                $cats = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($c in ($val -split ',')) {
                    $ct = $c.Trim().ToLower()
                    if ($ct) { [void]$cats.Add($ct) }
                }
                $meta['categories'] = $cats
            } else {
                $meta[$key] = $val
            }
        } else {
            $inHeader = $false
            $bodyLines.Add($line)
        }
    }

    $meta['body'] = ($bodyLines -join "`r`n")
    if (-not $meta.ContainsKey('categories')) {
        $meta['categories'] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    return $meta
}

function Format-PrintedDate {
    param([string]$dateStr)
    $parts = $dateStr -split '/'
    if ($parts.Count -eq 3) {
        $year = $parts[0]
        $monthNum = [int]$parts[1]
        $day = $parts[2]
        $months = @('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')
        $monthName = $months[$monthNum - 1]
        return "$year $monthName $day"
    }
    return $dateStr
}

function Get-RssPubDate {
    param([string]$dateStr)
    $parts = $dateStr -split '/'
    if ($parts.Count -eq 3) {
        $dt = [datetime]::new([int]$parts[0], [int]$parts[1], [int]$parts[2], 0, 0, 0, [DateTimeKind]::Utc)
        return $dt.ToString("ddd, dd MMM yyyy HH:mm:ss +0000", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return ""
}

# --- HTML Templates (matching Vitalik Buterin's blog generator style) ---

$PRE_HEADER = @"
<!DOCTYPE html>
<html>
<meta charset="UTF-8">
<style>
@media (prefers-color-scheme: dark) {
    body {
        background-color: #1c1c1c;
        color: white;
    }
    .markdown-body table tr {
        background-color: #1c1c1c;
    }
    .markdown-body table tr:nth-child(2n) {
        background-color: black;
    }
}
</style>

"@

$HEADER_TEMPLATE = @"

<link rel="stylesheet" type="text/css" href="`$root/css/common-vendor.b8ecfc406ac0b5f77a26.css">
<link rel="stylesheet" type="text/css" href="`$root/css/fretboard.f32f2a8d5293869f0195.css">
<link rel="stylesheet" type="text/css" href="`$root/css/pretty.0ae3265014f89d9850bf.css">
<link rel="stylesheet" type="text/css" href="`$root/css/pretty-vendor.83ac49e057c3eac4fce3.css">
<link rel="stylesheet" type="text/css" href="`$root/css/global.css">
<link rel="stylesheet" type="text/css" href="`$root/css/misc.css">

<script type="text/x-mathjax-config">
<script>
MathJax = {
  tex: {
    inlineMath: [['$', '$'], ['\\(', '\\)']]
  },
  svg: {
    fontCache: 'global',
  }
};
</script>
<script type="text/javascript" id="MathJax-script" async
  src="`$root/scripts/tex-svg.js">
</script>

<style>
</style>

<div id="doc" class="container-fluid markdown-body comment-enabled" data-hard-breaks="true">

<div id="color-mode-switch">
  <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
    <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
  </svg>
  <input type="checkbox" id="switch" />
  <label for="switch">Dark Mode Toggle</label>
  <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
    <path stroke-linecap="round" stroke-linejoin="round" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />
  </svg>
</div>
"@

$TOGGLE_COLOR_SCHEME_JS = @"
<script type="text/javascript">
  // Update root html class to set CSS colors
  const toggleDarkMode = () => {
    const root = document.querySelector('html');
    root.classList.toggle('dark');
  }

  // Update local storage value for colorScheme
  const toggleColorScheme = () => {
    const colorScheme = localStorage.getItem('colorScheme');
    if (colorScheme === 'light') localStorage.setItem('colorScheme', 'dark');
    else localStorage.setItem('colorScheme', 'light');
  }

  // Set toggle input handler
  const toggle = document.querySelector('#color-mode-switch input[type="checkbox"]');
  if (toggle) toggle.onclick = () => {
    toggleDarkMode();
    toggleColorScheme();
  }

  // Check for color scheme on init
  const checkColorScheme = () => {
    const colorScheme = localStorage.getItem('colorScheme');
    // Default to light for first view
    if (colorScheme === null || colorScheme === undefined) localStorage.setItem('colorScheme', 'light');
    // If previously saved to dark, toggle switch and update colors
    if (colorScheme === 'dark') {
      toggle.checked = true;
      toggleDarkMode();
    }
  }
  checkColorScheme();
</script>
"@

$FOOTER = " </div> "

# --- Main Build Process ---

Write-Host "=== Starting Blog Build ===" -ForegroundColor Cyan

# 1. Read Global Config
if (-not (Test-Path $ConfigPath)) {
    throw "Configuration file '$ConfigPath' not found!"
}
$globalConfig = Get-Metadata -FilePath $ConfigPath
$siteTitle = if ($globalConfig.ContainsKey('title')) { $globalConfig['title'] } else { "Notatki z historii" }
$siteIcon = if ($globalConfig.ContainsKey('icon')) { $globalConfig['icon'] } else { "http://vitalik.ca/images/icon.png" }
$siteDomain = if ($globalConfig.ContainsKey('domain')) { $globalConfig['domain'].TrimEnd('/') } else { "http://localhost:8080" }

# Clean posts_directory
$postsDirectory = if ($globalConfig.ContainsKey('posts_directory')) {
    $globalConfig['posts_directory'].TrimStart('.').TrimStart('/','\')
} else { "posts" }
if (-not $postsDirectory) { $postsDirectory = "posts" }

Write-Host "Site Title: $siteTitle"
Write-Host "Domain:     $siteDomain"
Write-Host "Posts Dir:  $postsDirectory"

# Create destination site directory
if (-not (Test-Path $SiteDir)) {
    [void](New-Item -ItemType Directory -Path $SiteDir -Force)
}

# 2. Process all Markdown Posts
$postFiles = Get-ChildItem -Path $PostsDir -Filter "*.md" | Where-Object { $_.Name -notmatch '\.sw[p-z]$' }
$metadatas = [System.Collections.Generic.List[hashtable]]::new()
$allCategories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($pf in $postFiles) {
    Write-Host "Processing: $($pf.Name)..." -ForegroundColor Yellow
    $meta = Get-Metadata -FilePath $pf.FullName -PostFilename $pf.Name
    
    if (-not $meta.ContainsKey('title')) {
        $meta['title'] = [System.IO.Path]::GetFileNameWithoutExtension($pf.Name)
    }
    if (-not $meta.ContainsKey('date')) {
        $meta['date'] = (Get-Date).ToString("yyyy/MM/dd")
    }

    # Relative path inside site: e.g. posts/2024/12/28/spis tresci.html
    $dateParts = $meta['date'] -split '/'
    $relDir = "$postsDirectory/$($dateParts[0])/$($dateParts[1])/$($dateParts[2])"
    $targetDir = Join-Path $SiteDir $relDir
    if (-not (Test-Path $targetDir)) {
        [void](New-Item -ItemType Directory -Path $targetDir -Force)
    }

    $outFilename = $meta['filename']
    $outPath = Join-Path $targetDir $outFilename

    # Relative root from post page is 4 levels up: ../../../..
    $rootPath = "../../../.."
    $printedDate = Format-PrintedDate $meta['date']
    $htmlContent = Convert-MarkdownToHtml -Markdown $meta['body']

    $rssLink = "`n<link rel=`"alternate`" type=`"application/rss+xml`" href=`"$rootPath/feed.xml`" title=`"$([System.Net.WebUtility]::HtmlEncode($meta['title']))`">`n"
    $twitterCard = "`n<meta name=`"twitter:card`" content=`"summary`" />`n<meta name=`"twitter:title`" content=`"$([System.Net.WebUtility]::HtmlEncode($meta['title']))`" />`n<meta name=`"twitter:image`" content=`"$siteIcon`" />`n"
    $titleHeader = @"

<br>
<h1 style="margin-bottom:7px"> $([System.Net.WebUtility]::HtmlEncode($meta['title'])) </h1>
<small style="float:left; color: #888"> $printedDate </small>
<small style="float:right; color: #888"><a href="$rootPath/index.html">See all posts</a></small>
<br> <br> <br>
<title> $([System.Net.WebUtility]::HtmlEncode($meta['title'])) </title>

"@

    $headerForPost = $HEADER_TEMPLATE.Replace('$root', $rootPath)

    $fullPostHtml = $PRE_HEADER + $rssLink + $headerForPost + $TOGGLE_COLOR_SCHEME_JS + $twitterCard + $titleHeader + $htmlContent + $FOOTER

    [System.IO.File]::WriteAllText($outPath, $fullPostHtml, [System.Text.Encoding]::UTF8)
    Write-Host " -> Generated: $relDir/$outFilename" -ForegroundColor Green

    # Copy any sibling asset subdirectories (e.g. images/, remont/) next to the post
    foreach ($subDir in (Get-ChildItem -Path (Split-Path $pf.FullName) -Directory)) {
        $assetDest = Join-Path $targetDir $subDir.Name
        if (-not (Test-Path $assetDest)) {
            [void](New-Item -ItemType Directory -Path $assetDest -Force)
        }
        Copy-Item -Path "$($subDir.FullName)\*" -Destination $assetDest -Recurse -Force
        Write-Host "   -> Copied assets: $($subDir.Name)/" -ForegroundColor DarkGreen
    }

    # Save metadata for TOC
    $meta['relUrl'] = "$relDir/$([System.Uri]::EscapeDataString($outFilename))"
    $meta['rawUrl'] = "$relDir/$outFilename"
    $metadatas.Add($meta)

    foreach ($cat in $meta['categories']) {
        [void]$allCategories.Add($cat)
    }
}

# 3. Sort Posts by date descending
$sortedMetadatas = $metadatas | Sort-Object -Property { $_['date'] } -Descending
$catList = $allCategories | Sort-Object

# Helper function to generate Table of Contents HTML
function New-TocHtml {
    param(
        [string]$Title,
        [string]$RootPath,
        [array]$Items,
        [string[]]$Categories
    )

    $rssLink = "`n<link rel=`"alternate`" type=`"application/rss+xml`" href=`"$RootPath/feed.xml`" title=`"$([System.Net.WebUtility]::HtmlEncode($Title))`">`n"
    $header = $HEADER_TEMPLATE.Replace('$root', $RootPath)
    $twitterCard = "`n<meta name=`"twitter:card`" content=`"summary`" />`n<meta name=`"twitter:title`" content=`"$([System.Net.WebUtility]::HtmlEncode($Title))`" />`n<meta name=`"twitter:image`" content=`"$siteIcon`" />`n"
    
    $tocTitle = @"

<title> $([System.Net.WebUtility]::HtmlEncode($Title)) </title>
<br>
<center><h1 style="border-bottom:0px"> $([System.Net.WebUtility]::HtmlEncode($Title)) </h1></center>

"@

    # Categories bar
    $catItems = [System.Collections.Generic.List[string]]::new()
    $catItems.Add('<center><hr>')
    foreach ($c in $Categories) {
        $cCap = (Get-Culture).TextInfo.ToTitleCase($c)
        $fontSize = [Math]::Min(100, [int](850 / [Math]::Max(1, $c.Length)))
        $catItems.Add("<span class=`"toc-category`" style=`"font-size:${fontSize}%`"><a href=`"$RootPath/categories/$c.html`">$cCap</a></span>")
    }
    $catItems.Add('<hr></center>')
    $catHeader = ($catItems -join "`n")

    $listItems = [System.Collections.Generic.List[string]]::new()
    $listItems.Add('<br><ul class="post-list" style="padding-left:0">')
    foreach ($m in $Items) {
        $pDate = Format-PrintedDate $m['date']
        $link = "$RootPath/$($m['relUrl'])"
        $mTitle = [System.Net.WebUtility]::HtmlEncode($m['title'])
        $listItems.Add(@"
<li>
    <span class="post-meta">$pDate</span>
    <h3 style="margin-top:12px">
      <a class="post-link" href="$link">$mTitle</a>
    </h3>
</li>
"@)
    }
    $listItems.Add('</ul>')

    return $PRE_HEADER + $rssLink + $header + $TOGGLE_COLOR_SCHEME_JS + $twitterCard + $tocTitle + $catHeader + ($listItems -join "`n") + $FOOTER
}

# 4. Generate Categories Pages
$catDir = Join-Path $SiteDir "categories"
if (-not (Test-Path $catDir)) {
    [void](New-Item -ItemType Directory -Path $catDir -Force)
}

foreach ($cat in $catList) {
    $cCap = (Get-Culture).TextInfo.ToTitleCase($cat)
    $catPosts = $sortedMetadatas | Where-Object { $_['categories'].Contains($cat) }
    $catHtml = New-TocHtml -Title $cCap -RootPath ".." -Items $catPosts -Categories $catList
    $catFilePath = Join-Path $catDir "$cat.html"
    [System.IO.File]::WriteAllText($catFilePath, $catHtml, [System.Text.Encoding]::UTF8)
    Write-Host " -> Generated category: categories/$cat.html" -ForegroundColor Green
}

# 5. Generate Homepage index.html
$indexHtml = New-TocHtml -Title $siteTitle -RootPath "." -Items $sortedMetadatas -Categories $catList
$indexPath = Join-Path $SiteDir "index.html"
[System.IO.File]::WriteAllText($indexPath, $indexHtml, [System.Text.Encoding]::UTF8)
Write-Host " -> Generated homepage: site/index.html" -ForegroundColor Green

# 6. Generate RSS feed.xml
$rssItems = [System.Collections.Generic.List[string]]::new()
foreach ($m in $sortedMetadatas) {
    $itemUrl = "$siteDomain/$($m['relUrl'])"
    $mTitle = [System.Net.WebUtility]::HtmlEncode($m['title'])
    $pubDate = Get-RssPubDate $m['date']
    $rssItems.Add(@"
<item>
<title>$mTitle</title>
<link>$itemUrl</link>
<guid>$itemUrl</guid>
<pubDate>$pubDate</pubDate>
<description></description>
</item>
"@)
}

$feedXml = @"
<?xml version="1.0" ?>
<rss version="2.0">
<channel>
  <title>$([System.Net.WebUtility]::HtmlEncode($siteTitle))</title>
  <link>$siteDomain/</link>
  <description>$([System.Net.WebUtility]::HtmlEncode($siteTitle))</description>
  <image>
      <url>$siteIcon</url>
      <title>$([System.Net.WebUtility]::HtmlEncode($siteTitle))</title>
      <link>$siteDomain/</link>
  </image>
$($rssItems -join "`n")
</channel>
</rss>
"@
$feedPath = Join-Path $SiteDir "feed.xml"
[System.IO.File]::WriteAllText($feedPath, $feedXml, [System.Text.Encoding]::UTF8)
Write-Host " -> Generated RSS feed: site/feed.xml" -ForegroundColor Green

# 7. Copy CSS and Scripts assets to site directory
Write-Host "Copying assets..." -ForegroundColor Yellow
$cssSource = "css"
$cssDest = Join-Path $SiteDir "css"
if (Test-Path $cssSource) {
    if (-not (Test-Path $cssDest)) { [void](New-Item -ItemType Directory -Path $cssDest -Force) }
    Copy-Item -Path "$cssSource\*" -Destination $cssDest -Recurse -Force
    Write-Host " -> Copied css to site/css" -ForegroundColor Green
}

$scriptsSource = "scripts"
$scriptsDest = Join-Path $SiteDir "scripts"
if (Test-Path $scriptsSource) {
    if (-not (Test-Path $scriptsDest)) { [void](New-Item -ItemType Directory -Path $scriptsDest -Force) }
    Copy-Item -Path "$scriptsSource\*" -Destination $scriptsDest -Recurse -Force
    Write-Host " -> Copied scripts to site/scripts" -ForegroundColor Green
}

$imagesSource = "images"
$imagesDest = Join-Path $SiteDir "images"
if (Test-Path $imagesSource) {
    if (-not (Test-Path $imagesDest)) { [void](New-Item -ItemType Directory -Path $imagesDest -Force) }
    Copy-Item -Path "$imagesSource\*" -Destination $imagesDest -Recurse -Force
    Write-Host " -> Copied images to site/images" -ForegroundColor Green
}

Write-Host "=== Build Completed Successfully! ===" -ForegroundColor Cyan

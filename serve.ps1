<#
.SYNOPSIS
    Starts a lightweight local HTTP server to preview the built blog site.
    Zero dependencies, runs on native Windows PowerShell.
#>

param(
    [int]$Port = 8080,
    [string]$Directory = "site"
)

$siteRoot = (Resolve-Path $Directory).Path
Write-Host "Serving '$siteRoot' on http://localhost:$Port/" -ForegroundColor Cyan

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Prefixes.Add("http://127.0.0.1:$Port/") } catch {}

try {
    $listener.Start()
} catch {
    Write-Warning "Port $Port is in use. Trying port 8081..."
    $Port = 8081
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$Port/")
    try { $listener.Prefixes.Add("http://127.0.0.1:$Port/") } catch {}
    $listener.Start()
}

Write-Host "Server listening at http://localhost:$Port/ (Press Ctrl+C to stop)" -ForegroundColor Green

$mimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".htm"  = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".xml"  = "application/rss+xml; charset=utf-8"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
    ".woff" = "font/woff"
    ".woff2"= "font/woff2"
    ".ttf"  = "font/ttf"
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $rawPath = [System.Uri]::UnescapeDataString($request.Url.AbsolutePath)
        if ($rawPath -eq "/" -or $rawPath -eq "") {
            $rawPath = "/index.html"
        }

        $relPath = $rawPath.TrimStart('/').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $localPath = Join-Path $siteRoot $relPath

        # If path is a directory and has index.html
        if (Test-Path $localPath -PathType Container) {
            $localPath = Join-Path $localPath "index.html"
        }

        # Check for fallback (e.g. trailing space variations on Windows)
        if (-not (Test-Path $localPath)) {
            $trimmedVariant = Join-Path (Split-Path $localPath) ((Split-Path $localPath -Leaf).Replace(" .html", ".html"))
            if (Test-Path $trimmedVariant) {
                $localPath = $trimmedVariant
            }
        }

        try {
            if (Test-Path $localPath -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($localPath).ToLower()
                $contentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { "application/octet-stream" }

                $bytes = [System.IO.File]::ReadAllBytes($localPath)

                $response.ContentType = $contentType
                $response.StatusCode = 200
                $response.ContentLength64 = $bytes.Length

                # Add CORS / cache headers for local dev preview
                $response.AddHeader("Access-Control-Allow-Origin", "*")
                $response.AddHeader("Cache-Control", "no-cache, no-store, must-revalidate")

                # Only write body for non-HEAD requests
                if ($request.HttpMethod -ne "HEAD") {
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                }
                $response.Close()
                Write-Host "[200] $rawPath ($($bytes.Length) bytes)" -ForegroundColor DarkGray
            } else {
                $msg = [System.Text.Encoding]::UTF8.GetBytes("<html><body><h1>404 Not Found</h1><p>$rawPath not found.</p></body></html>")
                $response.ContentType = "text/html; charset=utf-8"
                $response.StatusCode = 404
                $response.ContentLength64 = $msg.Length
                $response.OutputStream.Write($msg, 0, $msg.Length)
                $response.Close()
                Write-Warning "[404] $rawPath"
            }
        } catch {
            Write-Warning "[ERR] $rawPath - $_"
            try { $response.Abort() } catch {}
        }
    }
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}

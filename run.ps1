# AutoBounty - PowerShell Runner
# Complete pipeline execution for Windows

param(
    [switch]$SkipBuild,
    [switch]$ReportOnly,
    [switch]$Resume,
    [switch]$Clean,
    [switch]$CheckCRLF
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# Check CRLF in scripts
if ($CheckCRLF) {
    Write-Step "Checking for CRLF in scripts..."
    $crlf_found = $false
    Get-ChildItem -Path "scripts\*.sh" | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match "`r`n") {
            Write-Failure "CRLF detected in $($_.Name)"
            $crlf_found = $true
        }
    }
    if ($crlf_found) {
        Write-Host "`nTo fix: git add --renormalize . && git commit -m 'Normalize line endings'" -ForegroundColor Yellow
        exit 1
    }
    Write-Success "No CRLF detected"
    exit 0
}

# Clean output
if ($Clean) {
    Write-Step "Cleaning output directory..."
    if (Test-Path "output") {
        Remove-Item -Recurse -Force "output\*"
        Write-Success "Output cleaned"
    }
    exit 0
}

# Build runner image
if (-not $SkipBuild -and -not $ReportOnly) {
    Write-Step "Building runner Docker image..."
    docker compose build runner
    if ($LASTEXITCODE -ne 0) {
        Write-Failure "Build failed"
        exit 1
    }
    Write-Success "Build complete"
}

# Start containers
if (-not $ReportOnly) {
    Write-Step "Starting containers..."
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Failure "Failed to start containers"
        exit 1
    }
    Write-Success "Containers running"
}

# Run pipeline
if (-not $ReportOnly) {
    $resumeFlag = if ($Resume) { "RESUME=true" } else { "" }

    if ($Resume) {
        Write-Step "Resuming previous pipeline run..."
    } else {
        Write-Step "Executing recon pipeline..."
    }

    docker compose run --rm -e RESUME=$($Resume.ToString().ToLower()) runner bash -lc "bash /work/scripts/10_run_pipeline.sh"
    if ($LASTEXITCODE -ne 0) {
        Write-Failure "Pipeline failed"
        exit 1
    }
    Write-Success "Pipeline complete"
}

# Generate report
Write-Step "Generating report..."
docker compose run --rm runner bash -lc "bash /work/scripts/20_build_reports.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Failure "Report generation failed"
    exit 1
}
Write-Success "Report generated"

# Show results
if (Test-Path "output\LAST_RUN") {
    $run_id = Get-Content "output\LAST_RUN" -Raw
    $run_id = $run_id.Trim()
    $report_path = "output\$run_id\REPORT.md"

    if (Test-Path $report_path) {
        Write-Host "`n" -NoNewline
        Write-Step "Report Summary"
        Get-Content $report_path | Select-Object -First 25
        Write-Host "`nFull report: $report_path" -ForegroundColor Yellow
    }
}

Write-Success "`nAll done! Check output/<RUN_ID>/REPORT.md for results"

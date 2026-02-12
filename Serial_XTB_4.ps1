param(
    [string]$xtbPath = "C:\xtb\xtb.exe",
    [int]$Parallel = 8,
    [string]$RootFolder
)

# Prompt user for the root folder if not provided
if (-not $RootFolder) {
    $RootFolder = Read-Host "Enter the full path to the folder containing .xyz files"
}

# Prompt user for run type
Write-Host "Select run type:"
Write-Host "1: Geometry optimization (--opt vtight)"
Write-Host "2: Optimization + Hessian (--ohess vtight)"
Write-Host "3: Hessian only (--hess)"
$runChoice = Read-Host "Enter 1, 2, or 3"

switch ($runChoice) {
    '1' { $runType = 'opt' }
    '2' { $runType = 'ohess' }
    '3' { $runType = 'hess' }
    default {
        Write-Error "Invalid choice. Exiting."
        exit 1
    }
}

# Recursively find all .xyz files, excluding xtbopt.xyz unless Hessian-only run
$xyzFiles = Get-ChildItem -Path $RootFolder -Recurse -Filter *.xyz |
    Where-Object {
        if ($runType -eq 'hess') {
            $_.Name -eq "xtbopt.xyz"  # For Hessian-only, use xtbopt.xyz files
        } else {
            $_.Name -ne "xtbopt.xyz"  # For other runs, exclude xtbopt.xyz
        }
    } |
    Select-Object -ExpandProperty FullName

# Initialize summary lists
$successfulJobs = @()
$skippedJobs = @()

foreach ($xyzFile in $xyzFiles) {
    try {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($xyzFile)
        $parentDir = [System.IO.Path]::GetDirectoryName($xyzFile)
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

        # Add prefix based on run type
        $prefix = switch ($runType) {
            'opt'   { 'opt_' }
            'ohess' { 'ohess_' }
            'hess'  { 'hess_' }
        }

        $outputDir = Join-Path $parentDir "$prefix$baseName`_$timestamp"

        # Create timestamped output directory
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        $logFile = Join-Path $outputDir "$baseName.xtb.log"
        $errFile = Join-Path $outputDir "$baseName.xtb.err.log"

        # Resolve xtb executable
        if (-not (Test-Path $xtbPath)) {
            $cmd = Get-Command xtb -ErrorAction SilentlyContinue
            if ($cmd) {
                $xtbPath = $cmd.Source
            } else {
                Write-Warning "xtb executable not found. Skipping '$xyzFile'."
                $skippedJobs += $xyzFile
                continue
            }
        }

        # Check for input file
        if (-not (Test-Path $xyzFile)) {
            Write-Warning "Input file '$xyzFile' not found. Skipping."
            $skippedJobs += $xyzFile
            continue
        }

        Write-Host "Running xtb job for '$xyzFile' with mode: $runType"

        # Build arguments based on run type
        $arguments = @(
            '--chrg', '-5',
            '--uhf', '0',
            '--alpb', 'water',
            '--parallel', $Parallel.ToString()
        )

        switch ($runType) {
            'opt'   { $arguments += @('--opt', 'vtight') }
            'ohess' { $arguments += @('--ohess', 'vtight') }
            'hess'  { $arguments += '--hess' }
        }

        $arguments += $xyzFile

        # Run xtb
        $process = Start-Process -FilePath $xtbPath `
            -ArgumentList $arguments `
            -RedirectStandardOutput $logFile `
            -RedirectStandardError $errFile `
            -WorkingDirectory $outputDir `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -ErrorAction Stop

        if ($process.ExitCode -eq 0) {
            Write-Host "xtb job for '$xyzFile' completed successfully."
            $successfulJobs += $xyzFile
        } else {
            Write-Warning "xtb job for '$xyzFile' failed with exit code $($process.ExitCode). Skipping."
            $skippedJobs += $xyzFile
            continue
        }
    }
    catch {
        Write-Warning "Error processing '$xyzFile': $_.Exception.Message. Skipping."
        $skippedJobs += $xyzFile
        continue
    }
}

# Write summary log
$summaryPath = Join-Path $RootFolder "xtb_summary_log.txt"

"xtb Job Summary - $(Get-Date)" | Out-File $summaryPath
"----------------------------------------" | Out-File $summaryPath -Append
"Run Type: $runType" | Out-File $summaryPath -Append
"" | Out-File $summaryPath -Append
"Successful Jobs:" | Out-File $summaryPath -Append
$successfulJobs | Out-File $summaryPath -Append
"" | Out-File $summaryPath -Append
"Skipped Jobs:" | Out-File $summaryPath -Append
$skippedJobs | Out-File $summaryPath -Append

Write-Host "Summary log written to: $summaryPath"
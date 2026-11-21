param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 120,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$result = @{ ok = $false; message = ''; exit_code = -1 }
$lock = $null
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

function Invoke-GitProcess([string]$Arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $script:gitPath
    $info.Arguments = $Arguments
    $info.WorkingDirectory = $Repository
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $info.EnvironmentVariables['GCM_INTERACTIVE'] = 'Never'
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Could not launch Git.' }
        # Drain both pipes concurrently so a full error pipe cannot deadlock Git.
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $remaining = [Math]::Max(1, [int]($script:deadline - [DateTime]::UtcNow).TotalMilliseconds)
        if (-not $process.WaitForExit($remaining)) {
            $kill = New-Object System.Diagnostics.ProcessStartInfo
            $kill.FileName = Join-Path $env:SystemRoot 'System32/taskkill.exe'
            $kill.Arguments = "/PID $($process.Id) /T /F"
            $kill.UseShellExecute = $false
            $kill.CreateNoWindow = $true
            $killer = [System.Diagnostics.Process]::Start($kill)
            $null = $killer.WaitForExit(5000)
            $killer.Dispose()
            throw 'Push timed out. Check your connection and retry. If the upload reached GitHub, retrying is safe.'
        }
        return @{ code = $process.ExitCode; output = ($stdout.Result + $stderr.Result).Trim() }
    } finally {
        $process.Dispose()
    }
}

try {
    $Repository = (Resolve-Path -LiteralPath $Repository).Path
    $folder = Split-Path -Parent $ResultPath
    $null = New-Item -ItemType Directory -Force -Path $folder
    # File sharing lock prevents two editor instances from launching simultaneous pushes.
    $lock = [IO.File]::Open((Join-Path $folder 'push.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    $gitPath = if ($gitCommand) { $gitCommand.Source } else { Join-Path $env:ProgramFiles 'Git/cmd/git.exe' }
    if (-not (Test-Path -LiteralPath $gitPath)) { throw 'Git for Windows was not found. Install it and restart Godot.' }
    $status = Invoke-GitProcess 'status --porcelain'
    if ($status.code -ne 0) { throw $status.output }
    $localCount = @($status.output -split "`r?`n" | Where-Object { $_.Length -gt 0 }).Count
    # Override only this invocation: use the same HTTPS credential manager as CLI Git.
    # No tokens are read or saved by this plugin, and no SSH agent setup is required.
    $arguments = '-c credential.interactive=false -c url.https://github.com/.insteadOf=git@github.com: -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 push --porcelain origin'
    if ($DryRun) { $arguments += ' --dry-run' }
    $push = Invoke-GitProcess $arguments
    $result.exit_code = $push.code
    $result.ok = $push.code -eq 0
    $heading = if ($result.ok) { 'Push completed.' } else { 'Push failed. Your local commits and files are still safe.' }
    if ($DryRun) { $heading = if ($result.ok) { 'Push dry run succeeded; nothing was uploaded.' } else { 'Push dry run failed; nothing was uploaded.' } }
    $result.message = "$heading`n`n$($push.output)`n`n$localCount uncommitted/untracked files were not included. Stage and commit changes in the Git panel before pushing."
    if ($push.code -ne 0) {
        $result.message += "`n`nFor authentication errors, sign in once using Git Credential Manager outside Godot, then retry. For rejected updates, fetch and review the remote changes; this button never force-pushes."
    }
} catch {
    $result.message = "Background push could not finish: $($_.Exception.Message)`nYour working files were not modified."
} finally {
    if ($lock) { $lock.Dispose() }
    $json = $result | ConvertTo-Json
    [IO.File]::WriteAllText($ResultPath, $json, (New-Object Text.UTF8Encoding($false)))
}
if ($result.ok) { exit 0 } else { exit 1 }

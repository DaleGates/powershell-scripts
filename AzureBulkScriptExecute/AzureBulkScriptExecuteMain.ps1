
#Take in list .txt file with names on each line
param(
    [switch]$Debug = $false
)
$VMListItem = Get-Content -Path .\AzureBulkScriptInput.txt
# Set throttle limit (max amount of concurrent jobs)
$maxJobs = 5

# Sanity check of blank list 
if ($VMListItem -eq $null)
{
    Write-host "VM List is Empty please check ScriptInput.txt" -ForegroundColor Red
    exit
}

# User confirmation of listed VM's for user to ensure VM list is correct
if($Debug -eq $true) {Write-Host "DEBUG: ON" -ForegroundColor Cyan}
Write-Host "The following hosts will be affected:" -ForegroundColor Yellow
Write-Host $VMListItem 
Write-Host "---------------------------------"
$confirmation = Read-Host "Is this correct? [y/n]"
while($confirmation -ne "y") 
{
    if ($confirmation -eq 'n') 
    {
        Write-Host "Exiting..." -ForegroundColor Red
        exit
    }
    Write-Host "Incorrect selection please try again." -ForegroundColor Red
    Write-Host "The following hosts will be affected:" -ForegroundColor Yellow
    Write-Host $VMListItem
    $confirmation = Read-Host "Is this correct? [y/n]"
}

#Install modules if not already installed 
if(-not (Get-Module Az.Compute -ListAvailable)){
    Install-Module Az.Compute -Scope CurrentUser -Force 
}

if(-not (Get-Module Az.Accounts -ListAvailable)){
    Install-Module Az.Accounts -Scope CurrentUser -Force 
}

# Check user is logged in 
$context = Get-AzContext  
if (!$context) 
{
    Write-Host "Not signed in - please sign in to Azure" -ForegroundColor Red
    Connect-AzAccount
} 
else 
{
    if($using:Debug -eq $true) {Write-Host "Already connected to Azure"-ForegroundColor Green}
}

#initialise collections's
$errorVmCollection = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()
$notfoundvms = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()

#Start parallel execution of scripts
$VMListItem | ForEach-Object -Parallel{
    if($_.trim() -eq ""){
        if($using:Debug -eq $true) {Write-Host "DEBUG: Entry is blank - Moving on.." -ForegroundColor Cyan}
        break
    }
    function Invoke-AZVMLinux {
        param (
            [Parameter(Mandatory)]
            $vm
        )
        try {
            if($using:Debug -eq $true) {Write-Host "DEBUG: Invoking script on $($vm.name)" -ForegroundColor Cyan}
            $output = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName $vm.name -CommandID 'RunShellScript' -ScriptPath .\AzureBulkScript.sh -ErrorAction Stop
            $linux_dir = New-Item -ItemType Directory -Force -Path ".\$((Get-Date).ToString('yyyy-MM-dd'))_linux_run"
            Write-Host "Output for : $($vm.Name)"
            Write-Output –InputObject $output.Value[0].Message | Tee-Object -file "$linux_dir\$($vm.name).txt" -Append
        }
        catch {
            $errorMessage = Get-Error -Newest 1
            if($using:Debug -eq $true) {Write-Host "DEBUG: Error on $($vm.Name) : $($errorMessage.Exception.InnerException.Message)"-ForegroundColor Cyan}
            $errorObj += New-Object -TypeName psobject -Property @{VM=$($vm.Name);ERROR=$($errorMessage.Exception.InnerException.Message).ToString()}
            # Have to pull error collection local in order to write to back to it in a parallel Job
            $localerrorVmCollection = $using:errorVmCollection
            $localerrorVmCollection.Add($errorObj)

        }
    }
    function Invoke-AZVMWindows {
        param (
            [Parameter(Mandatory)]
            $vm
        )
        try {
            if($using:Debug -eq $true) {Write-Host "DEBUG: Invoking script on $($vm.name)" -ForegroundColor Cyan}
            $output = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName $vm.name -CommandID 'RunPowerShellScript' -ScriptPath .\AzureBulkScript.ps1 -ErrorAction Stop
            $linux_dir = New-Item -ItemType Directory -Force -Path ".\$((Get-Date).ToString('yyyy-MM-dd'))_windows_run"
            Write-Host "Output for : $($vm.Name)"
            Write-Output –InputObject $output.Value[0].Message | Tee-Object -file "$linux_dir\$($vm.name).txt" -Append
        }
        catch {
            $errorMessage = Get-Error -Newest 1
            if($using:Debug -eq $true) {Write-Host "DEBUG: Error on $($vm.Name) : $($errorMessage.Exception.InnerException.Message)" -ForegroundColor Cyan}
            $errorObj += New-Object -TypeName psobject -Property @{VM=$($vm.Name);ERROR=$($errorMessage.Exception.InnerException.Message).ToString()}
            # Have to pull error collection local in order to write to back to it in a parallel Job
            $localerrorVmCollection = $using:errorVmCollection
            $localerrorVmCollection.Add($errorObj)
        }
    }

    $SubscriptionList = Get-AzSubscription
    # Set current list item to variable
    $vm = $_
    # Reset vmfound variable 
    $vmfound = $False
    # Search through each subscription signed in user has access to 
    foreach ($Id in $SubscriptionList){

        if($using:Debug -eq $true) {Write-Host "DEBUG: Selecting Subscription: $($Id.Name) for $vm" -ForegroundColor Cyan}
        Select-AzSubscription $Id | Out-Null
        $azvm = Get-AzVM -Name $vm
        # Search for list item in the Azure Names first as this is quickest
        if ($azvm -ne $null){
            Write-host "VM: $vm has been found by Azure Name" -ForegroundColor Green
            if ($azvm.StorageProfile.OsDisk.OsType -contains "Linux"){
                Invoke-AZVMLinux -vm $azvm
            }
            # Run Powershell script if VM is Windows
            if ($azvm.StorageProfile.OsDisk.OsType -contains "Windows"){
                Invoke-AZVMWindows -vm $azvm
            }
            $vmfound = $True
            break 
        }
        # Break out of Subscription loop
        if ($vmfound -eq $true){
            break
        }
    }
    
    if ($vmfound -eq $false){
        # Have to pull not found collection local in order to write to back to it in a parallel Job
        $localNotFoundVM = $using:notfoundvms
        $localNotFoundVM.Add($vm.ToString())
    }
# Run 5 Jobs at once
} -ThrottleLimit $maxJobs

if ($errorVmCollection -ne $null){
    $error_dir = New-Item -ItemType Directory -Force -Path ".\$((Get-Date).ToString('yyyy-MM-dd'))_errorvms"
    Write-Host "Errored VM's: " -ForegroundColor Red
    $errorVmCollection | Format-Table 'VM','MESSAGE' -Wrap -AutoSize | Tee-Object -file "$error_dir\$((Get-Date).ToString('yyyy-MM-dd'))_errorLogs.txt" -Append
}

if ($notfoundvms -ne $null){
    $notfounddir = New-Item -ItemType Directory -Force -Path ".\$((Get-Date).ToString('yyyy-MM-dd'))_notfoundvms"
    Write-Host "VM's not found: " -ForegroundColor Yellow
    $notfoundvms | Format-Table 'VM','MESSAGE' -Wrap -AutoSize | Tee-Object -file "$notfounddir\$((Get-Date).ToString('yyyy-MM-dd'))_notfound_logs.txt" -Append
}

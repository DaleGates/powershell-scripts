
#Take in list .txt file with names on each line
param(
    [switch]$Debug = $false
)

$VMListItem = Get-Content -Path .\fedexBulkScriptInput.txt

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

#initialise collections's
$errorVmCollection = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()
$notfoundvms = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()

#Start parallel execution of scripts
$VMListItem | ForEach-Object -Parallel{
    function Invoke-AZVMLinux {
        param (
            [Parameter(Mandatory)]
            $vm
        )
        try {
            if($using:Debug -eq $true) {Write-Host "DEBUG: Invoking script on $($vm.name)" -ForegroundColor Cyan}
            $output = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName $vm.name -CommandID 'RunShellScript' -ScriptPath .\fedexBulkScript.sh -ErrorAction Stop
            $linux_dir = New-Item -ItemType Directory -Force -Path ".\$((Get-Date).ToString('yyyy-MM-dd'))_linux_run"
            Write-Host "Output for : $($vm.Name)"
            Write-Output –InputObject $output.Value[0].Message | Tee-Object -file "$linux_dir\$($vm.name).txt" -Append
        }
        catch {
            $errorMessage = Get-Error
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
            $output = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -VMName $vm.name -CommandID 'RunPowerShellScript' -ScriptPath .\fedexBulkScript.ps1 -ErrorAction Stop
            $linux_dir = New-Item -ItemType Directory -Force -Path ".\$((Get-Date).ToString('yyyy-MM-dd'))_windows_run"
            Write-Host "Output for : $($vm.Name)"
            Write-Output –InputObject $output.Value[0].Message | Tee-Object -file "$linux_dir\$($vm.name).txt" -Append
        }
        catch {
            $errorMessage = Get-Error 
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
    #Parse first 3 letters of vm name to pull fxi or tnt 
    $vmOrg = $vm.Substring(0,3)
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
} -ThrottleLimit 5

if ($errorVmCollection -ne $null){
    $error_dir = New-Item -ItemType Directory -Force -Path ".\$((Get-Date).ToString('yyyy-MM-dd'))_errorvms"
    Write-Host "Errored VM's: " -ForegroundColor Red
    $errorVmCollection | Format-Table -Wrap -AutoSize | Tee-Object -file "$error_dir\$((Get-Date).ToString('yyyy-MM-dd'))_errorLogs.txt" -Append
}

if ($notfoundvms -ne $null){
    $notfounddir = New-Item -ItemType Directory -Force -Path ".\$((Get-Date).ToString('yyyy-MM-dd'))_notfoundvms"
    Write-Host "VM's not found: " -ForegroundColor Yellow
    Write-Host ($notfoundvms -join "`n") -ForegroundColor Yellow | Tee-Object -file "$notfounddir\$((Get-Date).ToString('yyyy-MM-dd'))_notfound_logs.txt" -Append
}

#requires -version 7
<#
    .SYNOPSIS
    Extracts / process a list of flow logs in a given subscription and location

    .DESCRIPTION
    This script extracts a list of flow logs in a given subscription and location and generates a CSV file with the list of flow logs.
    The CSV file can be edited and passed again to the script to enable/disable/delete the flow logs according to the Status column in the CSV file ("Enabled", "Disabled", "Deleted").
    By specifying -WhatIf, the script will only show what would be done without actually doing it.

    .PARAMETER SubscriptionName
    The name of the subscription to use.

    .PARAMETER Location
    The Location to use.

    .PARAMETER CSVFile
    The path to the CSV file containing the list of NSG flow logs

    .PARAMETER NewCSV
    Generate a CSV file with the list of NSG flow logs in the given subscription and Location

    .PARAMETER SetCSV
    Read a CSV file with the list of NSG flow logs in the given subscription and Location and enable/disable/remove them according to the Status column in the CSV file ("Enabled", "Disabled", "Deleted")

    .EXAMPLE
    .\Change-FlowLogs.ps1 -SubscriptionName PRODUZIONE -Location ItalyNorth -CSVFile .\flowlogs.csv -SetCSV
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Specify the subscription name")]
    [string]$SubscriptionName,

    [Parameter(Mandatory = $false, HelpMessage = "Specify the Location to use")]
    [string]$Location,

    [Parameter(Mandatory = $false, HelpMessage = "Specify the path to the CSV file containing the list of NSG flow logs")]
    [string]$CSVFile,

    [Parameter(Mandatory = $false, HelpMessage = "Generate a CSV file with the list of NSG flow logs in the given subscription and Location")]
    [switch]$NewCSV,

    [Parameter(Mandatory = $false, HelpMessage = "Read a CSV file with the list of NSG flow logs in the given subscription and Location and enable/disable/delete them according to the Status column in the CSV file")]
    [switch]$SetCSV
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#############
# FUNCTIONS #
#############

### New-CSV ###
function New-CSV {
    $networkWatcher = Get-AzNetworkWatcher -Location $Location
    if (-not $networkWatcher) {
        throw "Network Watcher not found in Location $Location"
    }

    $networkWatcherflowlogs = Get-AzNetworkWatcherFlowLog -NetworkWatcher $networkWatcher

    # show the list of flow logs. For each one, take the name, the target resource (detects if NSG, VNet, subnet or single nic) and the status
    $flowlogs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    $networkWatcherflowlogs | Foreach-Object -ThrottleLimit ([Environment]::ProcessorCount) -Parallel {

        $flowlog = $_

        if ($flowlog.TargetResourceId -like "*resourceGroups*") {
            $flowlogType = "NSG"
        }
        elseif ($flowlog.TargetResourceId -like "*virtualNetworks*") {
            $flowlogType = "VNet"
        }
        elseif ($flowlog.TargetResourceId -like "*subnets*") {
            $flowlogType = "Subnet"
        }
        elseif ($flowlog.TargetResourceId -like "*networkInterfaces*") {
            $flowlogType = "NIC"
        }
        else {
            $flowlogType = "Unknown"
        }

        # extract the resource group name from the target resource id
        $ResourceGroupName = ($flowlog.TargetResourceId -split "/")[4]

        # extract the resource name from the target resource id
        $ResourceName = ($flowlog.TargetResourceId -split "/")[-1]

        # create flow log object
        $fl = [PSCustomObject]@{
            Name               = $flowlog.Name
            SubscriptionName   = $using:SubscriptionName
            Location           = $using:Location
            ResourceGroup      = $ResourceGroupName
            TargetResourceName = $ResourceName
            TargetResourceType = $flowlogType
            Status             = if ($flowlog.Enabled) { "Enabled" } else { "Disabled" }
        }

        # add the object to the list of flow logs
        ($using:flowlogs).Add($fl)
    }

    # print the flow logs
    $flowlogs | Format-Table -AutoSize

    # export the list of flow logs to a CSV file
    $flowlogs | Export-Csv -Path $CSVFile -NoTypeInformation
    Write-Host "CSV file $CSVFile generated."
}

### Set-CSV ###

function Set-CSV {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    if ($WhatIfPreference) {
        Write-Host -ForegroundColor Green "*** WhatIf mode enabled. No changes will be made."
    }

    # get the network watcher
    $networkWatcher = Get-AzNetworkWatcher -Location $Location
    if (-not $networkWatcher) {
        throw "Network Watcher not found in Location $($Location)"
    }

    # read the CSV file
    Write-Host "Reading CSV file $CSVFile..."
    $flowlogs = Import-Csv -Path $CSVFile

    # process the flow logs in parallel
    $flowlogs | Foreach-Object -ThrottleLimit ([Environment]::ProcessorCount) -Parallel {

        $flowlog = $_

        # get the flow log
        $networkWatcherflowlog = Get-AzNetworkWatcherFlowLog -NetworkWatcher $using:networkWatcher -Name $flowlog.Name
        Write-Host -NoNewline "Flow log "
        Write-Host -NoNewLine -ForegroundColor DarkYellow "$($flowlog.Name): "

        # enable or disable the flow log
        if ($flowlog.Status -eq "Enabled") {
            if (-not $networkWatcherflowlog.Enabled) {
                $networkWatcherflowlog.Enabled = $true
                $networkWatcherflowLog | Set-AzNetworkWatcherFlowLog -Force -WhatIf:$using:WhatIfPreference | Out-Null
                Write-Host -ForegroundColor Green "Enabled."
            }
            else {
                Write-Host "Ignored (already enabled)." -ForegroundColor Cyan
            }
        }
        elseif ($flowlog.Status -eq "Disabled") {
            if ($networkWatcherflowlog.Enabled) {
                $networkWatcherflowlog.Enabled = $false
                $networkWatcherflowLog | Set-AzNetworkWatcherFlowLog -Force -WhatIf:$using:WhatIfPreference | Out-Null
                Write-Host -ForegroundColor Yellow "Disabled."
            }
            else {
                Write-Host "Ignored (already disabled)." -ForegroundColor Cyan
            }
        }
        elseif ($flowlog.Status -eq "Deleted") {
            Remove-AzNetworkWatcherFlowLog -ResourceId $networkWatcherflowlog.Id -WhatIf:$using:WhatIfPreference | Out-Null
            Write-Host "Deleted." -ForegroundColor Red
        }
        else {
            throw "Invalid status $($flowlog.Status) for flow log $($flowlog.Name)"
        }
    }
}

########
# MAIN #
########

# verify that Az module is installed
if (-not (Get-Module -Name Az -ListAvailable)) {
    throw "You must install the Az module before running this script"
}

# verify that we have an active context
if (-not (Get-AzContext)) {
    throw "You must be logged in to Azure before running this script (use: Connect-AzAccount)"
}

# change the context to the specified subscription if needed
if ((Get-AzContext).Subscription.Name -ne $SubscriptionName) {
    Set-AzContext -SubscriptionName $SubscriptionName
}

# if GenerateCSV is specified, generate the CSV file and exit
if ($SetCSV) {
    Set-CSV
}

elseif ($NewCSV) {
    New-CSV
}

else {
    throw "You must specify either -NewCSV or -SetCSV"
}
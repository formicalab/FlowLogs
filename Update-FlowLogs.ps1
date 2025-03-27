#requires -version 7
<#
    .SYNOPSIS
    Extracts / process a list of flow logs

    .DESCRIPTION
    This script extracts and saves into a CSV file the list of all flow logs found in one or all subscriptions, and a given location.
    The CSV file can be edited and passed again to the script to enable/disable/delete the flow logs, according to the Status column in the CSV file ("Enabled", "Disabled", "Deleted","Updated").
    By specifying -WhatIf, the script will only show what would be done without actually doing it.
    If the subscription name is not specified, the script will use all subscriptions contained in the file also during the import phase; otherwise, only the specified subscription will be processed.

    .PARAMETER SubscriptionFilter
    The name of the subscription to use. If not specified, all subscriptions will be used.

    .PARAMETER Location
    The Location to use.

    .PARAMETER CSVFile
    The path to the CSV file containing the list of NSG flow logs

    .PARAMETER ExportCSV
    Generate a CSV file with the list of NSG flow logs in the given subscription and Location

    .PARAMETER ImportCSV
    Read a CSV file with the list of NSG flow logs in the given subscription and Location and enable/disable/remove them according to the Status column in the CSV file ("Enabled", "Disabled", "Deleted")

    .PARAMETER TenantId
    Tenant id or name (<name>.onmicrosoft.com) to use when operating on subscriptions. If not specified, the default tenant will be used.

    .EXAMPLE
    .\Change-FlowLogs.ps1 -SubscriptionName PRODUZIONE -Location italynorth -CSVFile .\flowlogs.csv -ImportCSV
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Specify the name of subscription to use. If not specified, all subscriptions will be used")]
    [string]$SubscriptionFilter,

    [Parameter(Mandatory = $false, HelpMessage = "Specify the Location to use")]
    [string]$Location,

    [Parameter(Mandatory = $false, HelpMessage = "Specify the path to the CSV file containing the list of NSG flow logs")]
    [string]$CSVFile,

    [Parameter(Mandatory = $false, HelpMessage = "Generate a CSV file with the list of NSG flow logs in the given subscription and Location")]
    [switch]$ExportCSV,

    [Parameter(Mandatory = $false, HelpMessage = "Read a CSV file with the list of NSG flow logs in the given subscription and Location and enable/disable/delete them according to the Status column in the CSV file")]
    [switch]$ImportCSV,

    [Parameter(Mandatory = $false, HelpMessage = "Default tenant id or name (<name>.onmicrosoft.com) to use when operating on subscriptions.")]
    [string]$TenantId = $null
)

Set-StrictMode -Version Latest

#################
### ExportCSV ###
#################
function ExportCSV {

    # if no subscription filter is specified, get all subscriptions
    if (-not $SubscriptionFilter) {
        Write-Host "No subscription filter specified. Getting the list of all subscriptions."
        $subscriptions = (Get-AzSubscription -TenantId $TenantId).Name
        if (-not $subscriptions) {
            throw "No subscriptions found - check your permissions."
        }
    }
    else {
        Write-Host "Note: a specific subscription was specified: $($SubscriptionFilter): processing only flow logs in this subscription." -ForegroundColor Yellow
        # put the single subscription name into an array
        $subscriptions = @($SubscriptionFilter)
    }

    $currentSubscription = (Get-AzContext).Subscription.Name
    $flowlogs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()    # thread-safe list of flow logs

    # loop through all subscriptions
    foreach ($subscription in $subscriptions) {

        Write-Host ("{0} ({1}): " -f $subscription, $Location) -NoNewline

        # change the context to the specified subscription if needed
        if ($subscription -ne $currentSubscription) {
            try {
                if ($TenantId) {
                    # do the actual change, even if -WhatIf is specified, to avoid verbose messages
                    Set-AzContext -SubscriptionName $subscription -TenantId $TenantId -ErrorAction Stop | Out-Null
                }
                else {
                    # do the actual change, even if -WhatIf is specified, to avoid verbose messages
                    Set-AzContext -SubscriptionName $subscription -ErrorAction Stop | Out-Null
                }
                $currentSubscription = $subscription
            }
            catch {
                throw "Failed to set subscription to $($subscription): $($_.Exception.Message)"
            }
        }

        $networkWatcherflowlogs = Get-AzNetworkWatcherFlowLog -Location $Location -ErrorAction SilentlyContinue
        if ($null -eq $networkWatcherflowlogs) {
            Write-Host "No flow logs found, skipping" -ForegroundColor DarkGray
            continue
        }
        else {
            $networkWatcherflowLogCount = if ($networkWatcherflowlogs -is [array]) { $networkWatcherflowlogs.Count } else { 1 }
            Write-Host "$networkWatcherflowLogCount flow logs found:"
        }

        # Prepare the list of flow logs. For each one, take the name, the target resource (detects if NSG, VNet, subnet or single nic) the status
        # Also, check if traffic analytics is enabled and in this case extract the interval
        $networkWatcherflowlogs | Foreach-Object -ThrottleLimit ([Environment]::ProcessorCount) -Parallel {

            $flowlog = $_

            if ($flowlog.TargetResourceId -like "*networkInterfaces*") {
                $flowlogType = "NIC"
            }
            elseif ($flowlog.TargetResourceId -like "*subnets*") {
                $flowlogType = "Subnet"
            }
            elseif ($flowlog.TargetResourceId -like "*virtualNetworks*") {
                $flowlogType = "VNet"
            }
            elseif ($flowlog.TargetResourceId -like "*networkSecurityGroups*") {
                $flowlogType = "NSG"
            }
            else {
                $flowlogType = "Unknown"
            }

            # extract the resource group name from the target resource id
            $ResourceGroupName = ($flowlog.TargetResourceId -split "/")[4]

            # extract the resource name from the target resource id
            $ResourceName = ($flowlog.TargetResourceId -split "/")[-1]

            if ($null -ne $flowlog.FlowAnalyticsConfiguration) {
                $TAInterval = $flowlog.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.TrafficAnalyticsInterval
            }
            else {
                $TAInterval = "N/A"
            }

            # create a new flow log object
            $fl = [PSCustomObject]@{
                Name               = $flowlog.Name
                SubscriptionName   = $using:subscription
                Location           = $using:Location
                ResourceGroup      = $ResourceGroupName
                TargetResourceName = $ResourceName
                TargetResourceType = $flowlogType
                Status             = if ($flowlog.Enabled) { "Enabled" } else { "Disabled" }
                TAInterval         = $TAInterval
            }

            # add the object to the list of flow logs
            ($using:flowlogs).Add($fl)
        }

        # print the flow logs found in this subscription
        $flowlogs | Where-Object { $_.SubscriptionName -eq $subscription } | ForEach-Object {
            $statusColor = "Cyan"
            if ($_.Status -like "*Enabled*") {
                $statusColor = "Green"
            }
            elseif ($_.Status -like "*Disabled*") {
                $statusColor = "Yellow"
            }
            Write-Host ("{0} ({1}): " -f $subscription, $Location) -NoNewline
            Write-Host ("({0}) " -f $_.TargetResourceType) -ForegroundColor Cyan -NoNewline
            Write-Host ("{0}: " -f $_.Name) -ForegroundColor White -NoNewline
            Write-Host $_.Status -ForegroundColor $statusColor -NoNewline
            if ($_.TAInterval -ne "N/A") {
                Write-Host (" (TA interval: {0})" -f $_.TAInterval) -ForegroundColor DarkGray
            }
            else {
                Write-Host ""
            }

        }
    }

    # export the list of flow logs to a CSV file
    $flowlogs | Export-Csv -Path $CSVFile -NoTypeInformation
    Write-Host "CSV file $CSVFile generated."
}

#################
### ImportCSV ###
#################

function ImportCSV {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    if ($WhatIfPreference) {
        Write-Host -ForegroundColor Green "*** WhatIf mode enabled. No changes will be made."
    }

    # verify that the CSV file exists
    if (-not (Test-Path $CSVFile)) {
        throw "CSV file $($CSVFile) not found"
    }

    # read the first line of the CSV file to determine the delimiter
    $delimiter = ""
    try {
        $delimiter = ((Get-Content -Path $CSVFile -TotalCount 1) -replace "[^,;]", "").Substring(0, 1)        
    }
    catch {
        throw "Cannot read the first line of the CSV file $($CSVFile) to detect delimiters: make sure the file is not empty and has the correct CSV format."
    }

    # read the CSV file
    Write-Host "Reading CSV file $CSVFile..."
    $csvFlowlogs = $null
    try {
        $csvFlowlogs = Import-Csv -Path $CSVFile -Delimiter $delimiter -ErrorAction Stop        
    }
    catch {
        throw "Failed to read CSV file $($CSVFile): $($_.Exception.Message)"
    }
    # ensure that the CSV file has the expected columns (Name, SubscriptionName, Location, ResourceGroup, TargetResourceName, TargetResourceType, Status)
    if (-not ($csvFlowlogs[0].PSObject.Properties.Name -contains "Name" -and
            $csvFlowlogs[0].PSObject.Properties.Name -contains "SubscriptionName" -and
            $csvFlowlogs[0].PSObject.Properties.Name -contains "Location" -and
            $csvFlowlogs[0].PSObject.Properties.Name -contains "ResourceGroup" -and
            $csvFlowlogs[0].PSObject.Properties.Name -contains "TargetResourceName" -and
            $csvFlowlogs[0].PSObject.Properties.Name -contains "TargetResourceType" -and
            $csvFlowlogs[0].PSObject.Properties.Name -contains "Status" -and
            $csvFlowlogs[0].PSObject.Properties.Name -contains "TAInterval")) {
        throw "Invalid CSV file format. The file must have the following columns: Name, SubscriptionName, Location, ResourceGroup, TargetResourceName, TargetResourceType, Status and TAInterval"
    }
    # sort the flow logs by subscription name
    $csvFlowLogs = $csvFlowlogs | Sort-Object -Property SubscriptionName
    $csvFlowLogsCount = if ($csvFlowlogs -is [array]) { $csvFlowlogs.Count } else { 1 }

    # count the number of flow logs and subscriptions
    $subscriptions = ($csvFlowlogs | Select-Object -ExpandProperty SubscriptionName -Unique)
    $subscriptionCount = if ($subscriptions -is [array]) { $subscriptions.Count } else { 1 }
    Write-Host "Found $($csvFlowLogsCount) flow logs in $($subscriptionCount) subscription(s) in the CSV file."

    # if a subscription filter was specified, check if it exists in the CSV file and use only that one
    if ($SubscriptionFilter) {
        if (-not ($subscriptions -contains $SubscriptionFilter)) {
            throw "Subscription $($SubscriptionFilter) not found in the CSV file"
        }
        Write-Host "Note: a specific subscription was specified: $($SubscriptionFilter): processing only flow logs in this subscription." -ForegroundColor Yellow
        $subscriptions = @($SubscriptionFilter)
    }
    
    $currentSubscription = (Get-AzContext).Subscription.Name
    $processedFlowLogs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()    # thread-safe list of processed flow logs

    # loop through all subscriptions
    foreach ($subscription in $subscriptions) {

        Write-Host ("{0}: " -f $subscription) -NoNewline

        # how many flow logs are in the file for this subscription?
        $flowlogsInSubscription = $csvFlowlogs | Where-Object { $_.SubscriptionName -eq $subscription } | Measure-Object | Select-Object -ExpandProperty Count
        if ($flowlogsInSubscription -eq 0) {
            Write-Host "No flow logs found in this subscription, skipping" -ForegroundColor DarkGray
            continue
        }
        Write-Host "($($flowlogsInSubscription) flow logs): " -NoNewline

        # change the context to the specified subscription if needed
        if ($subscription -ne $currentSubscription) {
            try {
                if ($TenantId) {
                    # do the actual change, even if -WhatIf is specified, to avoid verbose messages
                    Set-AzContext -SubscriptionName $subscription -TenantId $TenantId -ErrorAction Stop -WhatIf:$false | Out-Null
                }
                else {
                    # do the actual change, even if -WhatIf is specified, to avoid verbose messages
                    Set-AzContext -SubscriptionName $subscription -ErrorAction Stop -WhatIf:$false| Out-Null
                }
                $currentSubscription = $subscription
            }
            catch {
                throw "Failed to set subscription to $($subscription): $($_.Exception.Message)"
            }
        }

        $csvFlowlogs | Where-Object { $_.SubscriptionName -eq $subscription -and $_.Location -eq $Location } | Foreach-Object -ThrottleLimit ([Environment]::ProcessorCount) -Parallel {

            $flowlog = $_

            $networkWatcherflowlog = $null
            # get the actual flow log
            try {
                $networkWatcherflowlog = Get-AzNetworkWatcherFlowLog -Name $flowlog.Name -Location $flowlog.Location -ErrorAction Stop          
            }
            catch {
                $action = "FAILED to get: $($_.Exception.Message)"
            }

            if (-not $networkWatcherflowlog) {
                # if the flow log is not found or we had any other error, just skip it
            }
            elseif ($flowlog.Status -eq "Enabled") {
                if (-not $networkWatcherflowlog.Enabled) {
                    $networkWatcherflowlog.Enabled = $true
                    try {
                        $networkWatcherflowLog | Set-AzNetworkWatcherFlowLog -Force -WhatIf:$using:WhatIfPreference -ErrorAction Stop | Out-Null
                        $action = "Enabled"                        
                    }
                    catch {
                        $action = "FAILED to enable: $($_.Exception.Message)"
                    }
                }
                else {
                    $action = "Ignored (already enabled)"
                }
            }
            elseif ($flowlog.Status -eq "Disabled") {
                if ($networkWatcherflowlog.Enabled) {
                    $networkWatcherflowlog.Enabled = $false
                    try {
                        $networkWatcherflowLog | Set-AzNetworkWatcherFlowLog -Force -WhatIf:$using:WhatIfPreference -ErrorAction Stop | Out-Null
                        $action = "Disabled"                        
                    }
                    catch {
                        $action = "FAILED to disable: $($_.Exception.Message)"
                    }
                }
                else {
                    $action = "Ignored (already disabled)"
                }
            }
            elseif ($flowlog.Status -eq "Deleted") {
                try {
                    Remove-AzNetworkWatcherFlowLog -ResourceId $networkWatcherflowlog.Id -WhatIf:$using:WhatIfPreference -ErrorAction Stop | Out-Null                
                    $action = "Deleted"
                }
                catch {
                    $action = "FAILED to delete: $($_.Exception.Message)"
                }
            }
            elseif ($flowlog.Status -eq "Updated") {
                # update the flow log with the new TA interval
                try {
                    Set-AzNetworkWatcherFlowLog `
                    -Enabled $networkWatcherflowlog.Enabled `
                    -Name $networkWatcherflowlog.Name `
                    -TargetResourceId $networkWatcherflowlog.TargetResourceId `
                    -StorageId $networkWatcherflowlog.StorageId `
                    -EnableTrafficAnalytics:$networkWatcherflowlog.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.Enabled `
                    -TrafficAnalyticsInterval $flowlog.TAInterval `
                    -TrafficAnalyticsWorkspaceId $networkWatcherflowlog.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.WorkspaceResourceId `
                    -Location $networkWatcherflowlog.Location `
                    -Force -WhatIf:$using:WhatIfPreference -ErrorAction Stop | Out-Null
                    $action = "Updated"                        
                }
                catch {
                    $action = "FAILED to update: $($_.Exception.Message)"
                }
            }
            else {
                throw "Invalid status $($flowlog.Status) for flow log $($flowlog.Name)"
            }

            # log the action done on flow log
            $fl = [PSCustomObject]@{
                Name               = $flowlog.Name
                SubscriptioNName   = $flowlog.SubscriptionName
                TargetResourceType = $flowlog.TargetResourceType
                Action             = $action
            }
        
            # add the object to the list of processed flow logs for this subscription/location
            ($using:processedFlowlogs).Add($fl)

            # write progress dots
            Write-Host -NoNewline "." -ForegroundColor DarkGray
        }
        
        # print the processed flow logs for this subscription, with colored "Action" column
        Write-Host
        $processedFlowlogs | Where-Object { $_.SubscriptionName -eq $subscription } | ForEach-Object {
            $actionColor = "Cyan"
            if ($_.Action -like "*FAILED*") {
                $actionColor = "Red"
            }
            elseif ($_.Action -like "*Deleted*") {
                $actionColor = "DarkYellow"
            }
            elseif ($_.Action -like '*Ignored*') {
                $actionColor = "DarkGray"
            }
            elseif ($_.Action -like "*Enabled*") {
                $actionColor = "Green"
            }
            elseif ($_.Action -like "*Disabled*") {
                $actionColor = "Yellow"
            }

            Write-Host ("{0} ({1}): " -f $subscription, $Location) -NoNewline
            Write-Host ("({0}) " -f $_.TargetResourceType) -ForegroundColor Cyan -NoNewline
            Write-Host ("{0}: " -f $_.Name) -ForegroundColor White -NoNewline
            Write-Host $_.Action -ForegroundColor $actionColor
        }
    }

}

########
# MAIN #
########

# verify that Az module is installed
if (-not (Get-Module -Name Az -ListAvailable)) {
    throw "Please install the full Az module before running this script (https://learn.microsoft.com/en-us/powershell/azure/install-azps-windows)"
}

# verify that we have an active context
if (-not (Get-AzContext)) {
    throw "Please log in to Azure before running this script (use: Connect-AzAccount)"
}

# use all low case for the location
$Location = $Location.ToLower()

# if ExportCSV is specified, generate the CSV file and exit
if ($ExportCSV) {
    ExportCSV
}

# otherwise, if ImportCSV is specified, read the CSV file and process it
elseif ($ImportCSV) {
    ImportCSV
}

else {
    throw "Please specify either -ExportCSV or -ImportCSV"
}
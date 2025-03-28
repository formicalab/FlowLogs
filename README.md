### Update-FlowLogs

When used with the `ExportCSV` parameter, this script extracts all flow logs (NSG or VNet) found in one or all subscriptions and in the specified location, and generates a CSV file with their details.

The CSV file can then be edited and passed again to the script, with the `ImportCSV` parameter,  to enable/disable/delete the flow logs, according to the values set in the **Status** column in the CSV file (`Enabled`, `Disabled`, `Deleted`, `Updated`). For maximum safety, by specifying `-WhatIf`, the script will only show what would be done without actually doing it.

Based on the **Status** column, the following happens:
* `Enabled`: the flow log is enabled. If already enabled, nothing happens
* `Disabled`: the flow log is disabled. If already disabled, nothing happens
* `Deleted`: the flow log is deleted
* `Updated`: the Traffic Analytics Interval (TAInterval) is updated

Example to get the current flow logs from all subscriptions:

    .\Update-FlowLogs.ps1 -Location westeurope -CSVFile .\flowlogs.csv -ExportCSV

Once the CSV has been edited to specify which flows should be enabled, disabled or deleted, execute the following to apply the changes:

    .\Update-FlowLogs.ps1 -Location westeurope -CSVFile .\flowlogs.csv -ImportCSV

You can use `-SubscriptionFilter` <subscription name> to limit actions to a specific subscription, instead of all:

        .\Update-FlowLogs.ps1 -SubscriptionFilter SUB-PRODUZIONE -Location westeurope -CSVFile .\flowlogs.csv -ExportCSV

Add `-TenantId` to specify which tenant to use (in case your user can login to different tenants)

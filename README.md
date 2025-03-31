### Update-FlowLogs

When used with the `ExportCSV` parameter, this script extracts all flow logs (NSG or VNet) found in a given subscription and location and generates a CSV file with their list.

The CSV file can then be edited and passed again to the script, with the `ImportCSV` parameter,  to enable/disable/delete the flow logs, according to the values set in the **Status** column in the CSV file (`Enabled`, `Disabled`, `Deleted`). For maximum safety, by specifying `-WhatIf`, the script will only show what would be done without actually doing it.

Example to get the current flow logs:

    .\Update-FlowLogs.ps1 -SubscriptionName PRODUZIONE -Location ItalyNorth -CSVFile .\flowlogs.csv -ExportCSV

Once the CSV has been edited to specify which flows should be enabled, disabled or deleted, execute the following to apply the changes:

    .\Update-FlowLogs.ps1 -SubscriptionName PRODUZIONE -Location ItalyNorth -CSVFile .\flowlogs.csv -ImportCSV

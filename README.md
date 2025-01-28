### Change-FlowLogs

This script extracts a list of flow logs in a given subscription and location and generates a CSV file with the list of flow logs.

The CSV file can then be edited and passed again to the script to enable/disable/delete the flow logs, according to the values set in the **Status** column in the CSV file (`Enabled`, `Disabled`, `Deleted`).

By specifying `-WhatIf`, the script will only show what would be done without actually doing it.

Example to get the current flow logs:

    .\Change-FlowLogs.ps1 -SubscriptionName PRODUZIONE -Location ItalyNorth -CSVFile .\flowlogs.csv -NewCSV

Example to modify the flow logs:

    .\Change-FlowLogs.ps1 -SubscriptionName PRODUZIONE -Location ItalyNorth -CSVFile .\flowlogs.csv -SetCSV

### Update-FlowLogs.ps1

When used with the `ExportCSV` parameter, this script extracts all flow logs (NSG or VNet) found in a given subscription and location and generates a CSV file with their list.

The CSV file can then be edited and passed again to the script, with the `ImportCSV` parameter,  to enable/disable/update/delete the flow logs, according to the values set in the **Status** column in the CSV file (`Enabled`, `Disabled`, `Disabled`, `Deleted`). For maximum safety, by specifying `-WhatIf`, the script will only show what would be done without actually doing it.

Example to get the current flow logs:

    .\Update-FlowLogs.ps1 -SubscriptionName PRODUZIONE -Location ItalyNorth -CSVFile .\flowlogs.csv -ExportCSV

Once the CSV has been edited to specify which flows should be enabled, disabled or deleted, execute the following to apply the changes:

    .\Update-FlowLogs.ps1 -SubscriptionName PRODUZIONE -Location ItalyNorth -CSVFile .\flowlogs.csv -ImportCSV


### Policy

This project also contains an Azure Policy (file `policy.json`) that can be used to create flow logs and associated Traffic Analytics configurations for all subnets with an associated NSG. The purpose of the policy is to re-create the old behavior of the NSG flow logs (working only with NSGs).

To use the policy:
1. create a user-assigned managed identity
2. assign the following custom role to the identity, at management group level:

```
        "permissions": [
            {
                "actions": [
                    "Microsoft.Network/networkWatchers/read",
                    "Microsoft.Network/networkWatchers/write",
                    "Microsoft.Network/networkWatchers/configureFlowLog/action",
                    "Microsoft.Network/networkWatchers/queryFlowLogStatus/action",
                    "Microsoft.Storage/storageAccounts/listServiceSas/action",
                    "Microsoft.Storage/storageAccounts/listAccountSas/action",
                    "Microsoft.Storage/storageAccounts/listkeys/action",
                    "Microsoft.Network/applicationGateways/read",
                    "Microsoft.Network/connections/read",
                    "Microsoft.Network/loadBalancers/read",
                    "Microsoft.Network/localNetworkGateways/read",
                    "Microsoft.Network/networkInterfaces/read",
                    "Microsoft.Network/networkSecurityGroups/read",
                    "Microsoft.Network/publicIPAddresses/read",
                    "Microsoft.Network/routeTables/read",
                    "Microsoft.Network/virtualNetworkGateways/read",
                    "Microsoft.Network/virtualNetworks/read",
                    "Microsoft.Network/expressRouteCircuits/read",
                    "Microsoft.OperationalInsights/workspaces/read",
                    "Microsoft.OperationalInsights/workspaces/sharedkeys/action",
                    "Microsoft.Insights/dataCollectionRules/read",
                    "Microsoft.Insights/dataCollectionRules/write",
                    "Microsoft.Insights/dataCollectionRules/delete",
                    "Microsoft.Insights/dataCollectionEndpoints/read",
                    "Microsoft.Insights/dataCollectionEndpoints/write",
                    "Microsoft.Insights/dataCollectionEndpoints/delete",
                    "Microsoft.Network/networkWatchers/flowLogs/read",
                    "Microsoft.Network/networkWatchers/flowLogs/write",
                    "Microsoft.Network/networkWatchers/flowLogs/delete",
                    "Microsoft.Resources/deployments/write",
                    "Microsoft.Network/virtualNetworks/subnets/write",
                    "Microsoft.Network/virtualNetworks/subnets/read"
                ],
                "notActions": [],
                "dataActions": [],
                "notDataActions": []
            }
        ]
```

3. at policy assignment, create a remediation task by specifying the user-assigned managed identity as identity to use for remediation activities
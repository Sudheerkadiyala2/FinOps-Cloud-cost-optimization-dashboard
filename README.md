
                           ┌────────────────────────────┐
                           │        Frontend UI         │
                           │----------------------------│
                           │ React / Angular Dashboard  │
                           │                            │
                           │ - Findings Table           │
                           │ - Savings Cards            │
                           │ - Trends Graphs            │
                           │ - Filters/Search           │
                           │ - Governance Dashboard     │
                           │ - Cost Analytics           │
                           └────────────┬───────────────┘
                                        │
                                        │ HTTPS Requests
                                        ▼

                           ┌────────────────────────────┐
                           │        API Gateway         │
                           │----------------------------│
                           │  GET /findings             │
                           │  GET /summary              │
                           │  GET /trends               │
                           └────────────┬───────────────┘
                                        │
                                        │ Invoke APIs
                                        ▼

                      ┌─────────────────────────────────────┐
                      │  cost-intelligence-api Lambda       │
                      │-------------------------------------│
                      │                                     │
                      │ - Read DynamoDB findings            │
                      │ - Aggregate summaries               │
                      │ - Generate trends response          │
                      │ - Return frontend JSON APIs         │
                      └────────────────┬────────────────────┘
                                       │
                                       │ Query findings
                                       ▼

                      ┌─────────────────────────────────────┐
                      │      DynamoDB Findings Table        │
                      │-------------------------------------│
                      │  cost-waste-findings               │
                      │                                     │
                      │ Stores:                             │
                      │ - wasteType                         │
                      │ - severity                          │
                      │ - recommendation                    │
                      │ - estimatedSavings                  │
                      │ - status                            │
                      │ - resource metadata                 │
                      └────────────────┬────────────────────┘
                                       │
                                       │ Findings inserted
                                       ▼

                      ┌─────────────────────────────────────┐
                      │      waste_detector Lambda          │
                      │-------------------------------------│
                      │                                     │
                      │ Detects:                            │
                      │ - Idle EC2                          │
                      │ - Unused Elastic IPs                │
                      │ - Unattached EBS                    │
                      │                                     │
                      │ Generates governance findings       │
                      │ Calculates estimated savings        │
                      └────────────────┬────────────────────┘
                                       │
                                       │ Triggered automatically
                                       ▼

                      ┌─────────────────────────────────────┐
                      │       S3 Event Notification         │
                      └────────────────┬────────────────────┘
                                       │
                                       │ New raw JSON uploaded
                                       ▼

                      ┌─────────────────────────────────────┐
                      │           S3 Bucket                 │
                      │-------------------------------------│
                      │ raw-data/*.json                     │
                      │                                     │
                      │ Historical infrastructure snapshots │
                      └────────────────┬────────────────────┘
                                       │
                                       │ Upload collected data
                                       ▼

                      ┌─────────────────────────────────────┐
                      │      cost_collector Lambda          │
                      │-------------------------------------│
                      │                                     │
                      │ Collects:                           │
                      │ - EC2 inventory                     │
                      │ - EBS volumes                       │
                      │ - Elastic IPs                       │
                      │ - CloudWatch metrics                │
                      │                                     │
                      │ Generates infrastructure snapshots  │
                      └────────────────┬────────────────────┘
                                       │
                                       │ Scheduled trigger
                                       ▼

                      ┌─────────────────────────────────────┐
                      │         EventBridge Rule            │
                      │-------------------------------------│
                      │ rate(1 day)                         │
                      │                                     │
                      │ Automated daily collection          │
                      └────────────────┬────────────────────┘
                                       │
                                       │ Calls AWS APIs
                                       ▼

          ┌────────────────────────────────────────────────────────────┐
          │                        AWS APIs                            │
          │------------------------------------------------------------│
          │                                                            │
          │ EC2 APIs:                                                   │
          │ - DescribeInstances                                         │
          │ - DescribeVolumes                                           │
          │ - DescribeAddresses                                         │
          │                                                            │
          │ CloudWatch APIs:                                            │
          │ - GetMetricStatistics                                       │
          │                                                            │
          └────────────────────────────────────────────────────────────┘

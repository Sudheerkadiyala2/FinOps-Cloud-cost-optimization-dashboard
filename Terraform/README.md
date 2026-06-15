# ============================================================
# terraform/README.md
# How to deploy the entire platform from scratch.
# Need of terraform-we can create infra manually for 2.but not 200 
# 
# ============================================================

# Terraform — Infrastructure as Code

Provisions every AWS resource needed for the Cloud Cost Intelligence Platform with a single command.

## What gets created

| Resource | Name |
|---|---|
| S3 Bucket | `sudheer-cost-intelligence` |
| DynamoDB Table | `cost-waste-findings` |
| Lambda: cost_collector | `cost-intelligence-cost-collector` |
| Lambda: waste_detector | `cost-intelligence-waste-detector` |
| Lambda: api | `cost-intelligence-api` |
| API Gateway HTTP API | `cost-intelligence-api` |
| EventBridge Rule | `cost-intelligence-daily-collection` |
| IAM Roles (3) | One per Lambda — least privilege |
| CloudWatch Log Groups (4) | 30-day retention |
| CloudWatch Alarms (3) | Error rate monitoring |

## Prerequisites

- Terraform >= 1.6.0 — [install](https://developer.hashicorp.com/terraform/install)
- AWS CLI configured — `aws configure`
- AWS account with permissions to create Lambda, S3, DynamoDB, IAM, API Gateway

## Deploy

```bash
cd terraform/

# 1. Initialise — downloads AWS provider
terraform init

# 2. Preview what will be created (no changes made yet)
terraform plan

# 3. Deploy everything
terraform apply

# Type "yes" when prompted
```

After apply completes, the API URL is printed in the output.

## Destroy (tear everything down)

```bash
terraform destroy
```

**Warning:** This deletes the DynamoDB table and all findings data. S3 bucket must be empty first:
```bash
aws s3 rm s3://sudheer-cost-intelligence --recursive
terraform destroy
```

## Customise

Edit `variables.tf` to change:
- `aws_region` — deploy to a different region
- `s3_bucket_name` — must be globally unique
- `schedule_expression` — change the daily collection time
- `slack_webhook_url` — add Slack alerts

## File structure

```
terraform/
├── main.tf          # provider config + common tags
├── variables.tf     # all configurable values
├── storage.tf       # S3 bucket + DynamoDB table
├── iam.tf           # IAM roles and policies (Least privilage policy)
├── lambdas.tf       # all 3 Lambda functions
├── api_gateway.tf   # HTTP API Gateway + routes
├── scheduler.tf     # EventBridge schedule + CloudWatch alarms
├── outputs.tf       # values printed after deploy
└── README.md        # this file
```

# ============================================================
# variables.tf
# All configurable values live here.
# Change these to deploy to a different account or region.
# ============================================================

variable "aws_region" {
  description = "AWS region to deploy everything into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for all resource names — keeps everything grouped in AWS console"
  type        = string
  default     = "cost-intelligence"
}

variable "environment" {
  description = "Deployment environment — used in tags"
  type        = string
  default     = "prod"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket that stores raw cost data. Must be globally unique."
  type        = string
  default     = "sudheer-cost-intelligence"
  # Change this to your actual bucket name if deploying fresh
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table that stores waste findings"
  type        = string
  default     = "cost-waste-findings"
}

variable "lambda_runtime" {
  description = "Python runtime for all Lambda functions"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds. 300 = 5 minutes — enough for large accounts"
  type        = number
  default     = 300
}

variable "lambda_memory" {
  description = "Lambda memory in MB. 256 is enough for all 3 functions"
  type        = number
  default     = 256
}

variable "schedule_expression" {
  description = "EventBridge cron for the daily cost_collector run. Default = 8AM UTC daily."
  type        = string
  default     = "cron(0 8 * * ? *)"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for waste alerts. Leave empty to disable Slack notifications."
  type        = string
  default     = ""
  sensitive   = true   # marks this as sensitive — Terraform won't print it in logs
}

variable "owner" {
  description = "Your name — used in resource tags for attribution"
  type        = string
  default     = "sudheer"
}

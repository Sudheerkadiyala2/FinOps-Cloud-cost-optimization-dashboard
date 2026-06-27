# ============================================================
# iam.tf
# IAM execution roles and policies for all 3 Lambda functions.
# Each Lambda gets its own role with only the permissions it needs.
# This is the principle of least privilege.
# ============================================================


# ── Shared: CloudWatch Logs policy ───────────────────────────────────────────
# All 3 Lambdas need to write logs to CloudWatch.
# We define this once and attach to all 3 roles.

resource "aws_iam_policy" "lambda_logging" {
  name        = "${var.project_name}-lambda-logging"
  description = "Allow Lambda functions to write logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",    # create the /aws/lambda/function-name log group
          "logs:CreateLogStream",   # create a new log stream for each invocation
          "logs:PutLogEvents"       # write actual log lines
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}


# ═══════════════════════════════════════════════════════════════════════════════
# ROLE 1: cost_collector Lambda
# Needs: EC2 read, CloudWatch read, S3 write, Cost Explorer read
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "cost_collector" {
  name = "${var.project_name}-cost-collector-role"

  # Trust policy: only Lambda can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "cost_collector" {
  name        = "${var.project_name}-cost-collector-policy"
  description = "Permissions for cost_collector Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read EC2 resource inventory
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeInstances",     # list all EC2 instances
          "ec2:DescribeVolumes",       # list all EBS volumes
          "ec2:DescribeAddresses",     # list all Elastic IPs
          "ec2:DescribeRegions"        # list available regions
        ]
        Resource = "*"   # EC2 Describe actions don't support resource-level restrictions
      },
      {
        # Read CloudWatch metrics (CPU, network etc.)
        Effect   = "Allow"
        Action   = [
          "cloudwatch:GetMetricStatistics",   # get historical metric data
          "cloudwatch:PutMetricData"          # publish custom DailySpend metric
        ]
        Resource = "*"
      },
      {
        # Write raw cost snapshots to S3
        Effect   = "Allow"
        Action   = [
          "s3:PutObject",   # upload the JSON snapshot
          "s3:GetObject"    # read back if needed
        ]
        Resource = "${aws_s3_bucket.cost_data.arn}/*"
        # /* means any object inside the bucket — not the bucket itself
      },
      {
        # Read AWS billing data via Cost Explorer
        Effect   = "Allow"
        Action   = [
          "ce:GetCostAndUsage",                    # get spend by service, date range
          "ce:UpdateCostAllocationTagsStatus"      # enable team tags for attribution
        ]
        Resource = "*"   # Cost Explorer doesn't support resource-level permissions
      }
    ]
  })
}

# Attach the custom policy to the role
resource "aws_iam_role_policy_attachment" "cost_collector_policy" {
  role       = aws_iam_role.cost_collector.name
  policy_arn = aws_iam_policy.cost_collector.arn
}

# Attach the shared logging policy
resource "aws_iam_role_policy_attachment" "cost_collector_logging" {
  role       = aws_iam_role.cost_collector.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}


# ═══════════════════════════════════════════════════════════════════════════════
# ROLE 2: waste_detector Lambda
# Needs: S3 read, EC2 read, CloudWatch read, DynamoDB write
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "waste_detector" {
  name = "${var.project_name}-waste-detector-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "waste_detector" {
  name        = "${var.project_name}-waste-detector-policy"
  description = "Permissions for waste_detector Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read the raw snapshot file from S3
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.cost_data.arn}/*"
      },
      {
        # Read EC2 resources for waste analysis
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeAddresses"
        ]
        Resource = "*"
      },
      {
        # Read CloudWatch metrics for CPU analysis
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricStatistics"]
        Resource = "*"
      },
      {
        # Write findings to DynamoDB
        Effect   = "Allow"
        Action   = [
          "dynamodb:PutItem",      # write new finding
          "dynamodb:UpdateItem",   # update existing finding
          "dynamodb:Query",        # query by resourceId
          "dynamodb:GetItem"       # read one item (for cooldown check)
        ]
        # Scope to our specific table only — not all DynamoDB tables
        Resource = [
          aws_dynamodb_table.cost_waste_findings.arn,
          "${aws_dynamodb_table.cost_waste_findings.arn}/index/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "waste_detector_policy" {
  role       = aws_iam_role.waste_detector.name
  policy_arn = aws_iam_policy.waste_detector.arn
}

resource "aws_iam_role_policy_attachment" "waste_detector_logging" {
  role       = aws_iam_role.waste_detector.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}


# ═══════════════════════════════════════════════════════════════════════════════
# ROLE 3: cost_intelligence_api Lambda
# Needs: DynamoDB read, S3 read
# This is the most restricted role — API only reads, never writes
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "api" {
  name = "${var.project_name}-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "api" {
  name        = "${var.project_name}-api-policy"
  description = "Permissions for cost_intelligence_api Lambda — read only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read findings from DynamoDB
        Effect   = "Allow"
        Action   = [
          "dynamodb:Scan",         # get all findings
          "dynamodb:Query",        # query by status
          "dynamodb:GetItem",      # get one finding
          "dynamodb:UpdateItem"    # mark finding as resolved
        ]
        Resource = [
          aws_dynamodb_table.cost_waste_findings.arn,
          "${aws_dynamodb_table.cost_waste_findings.arn}/index/*"
        ]
      },
      {
        # Read trends data from S3
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.cost_data.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_policy" {
  role       = aws_iam_role.api.name
  policy_arn = aws_iam_policy.api.arn
}

resource "aws_iam_role_policy_attachment" "api_logging" {
  role       = aws_iam_role.api.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

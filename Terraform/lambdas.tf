# ============================================================
# lambdas.tf
# All 3 Lambda functions: cost_collector, waste_detector, api.
# Each Lambda is packaged from the local lambdas/ folder.
# ============================================================


# ── Package: zip each Lambda folder before deploying ────────────────────────
# archive_file reads the source code from disk and creates a zip file.
# Terraform uploads the zip to Lambda automatically.

data "archive_file" "cost_collector" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/cost_collector"             # ../lambdas/cost_collector = the Lambda source code folder
  output_path = "${path.module}/.lambda_zips/cost_collector.zip"      #  path.module = the terraform/ director
      }                                                                     # ../lambdas/cost_collector = the Lambda source code folder              

data "archive_file" "waste_detector" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/waste_detector"
  output_path = "${path.module}/.lambda_zips/waste_detector.zip"
}

data "archive_file" "api" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/api"
  output_path = "${path.module}/.lambda_zips/api.zip"
}


# ═══════════════════════════════════════════════════════════════════════════════
# LAMBDA 1: cost_collector
# Triggered by EventBridge daily schedule
# Collects EC2, EBS, EIP inventory + CloudWatch metrics
# Uploads raw JSON snapshot to S3
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_lambda_function" "cost_collector" {
  function_name = "${var.project_name}-cost-collector"
  description   = "Collects AWS resource inventory and uploads to S3"

  # The zipped source code
  filename         = data.archive_file.cost_collector.output_path
  source_code_hash = data.archive_file.cost_collector.output_base64sha256
  # source_code_hash: Terraform compares this hash on every apply.
  # If the code changed, it redeploys. If nothing changed, it skips.

  runtime = var.lambda_runtime   # python3.12
  handler = "handler.lambda_handler"
  # handler = "filename.function_name" inside the zip

  timeout     = var.lambda_timeout   # 300 seconds = 5 minutes
  memory_size = var.lambda_memory    # 256 MB

  role = aws_iam_role.cost_collector.arn

  # Environment variables — accessible in Python via os.environ['KEY']
  environment {
    variables = {
      COST_BUCKET          = var.s3_bucket_name
      DYNAMODB_TABLE       = var.dynamodb_table_name
      AWS_ACCOUNT_REGION   = var.aws_region
      SLACK_WEBHOOK_URL    = var.slack_webhook_url
    }
  }
}

# Allow EventBridge to invoke cost_collector
resource "aws_lambda_permission" "eventbridge_invoke_cost_collector" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_collector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_collection.arn
}


# ═══════════════════════════════════════════════════════════════════════════════
# LAMBDA 2: waste_detector
# Triggered by S3 event when cost_collector uploads a new file
# Reads the snapshot, detects waste, writes findings to DynamoDB
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_lambda_function" "waste_detector" {
  function_name = "${var.project_name}-waste-detector"
  description   = "Detects AWS resource waste and writes findings to DynamoDB"

  filename         = data.archive_file.waste_detector.output_path
  source_code_hash = data.archive_file.waste_detector.output_base64sha256

  runtime = var.lambda_runtime
  handler = "handler.lambda_handler"

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory

  role = aws_iam_role.waste_detector.arn

  environment {
    variables = {
      COST_BUCKET       = var.s3_bucket_name
      DYNAMODB_TABLE    = var.dynamodb_table_name
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }
}

# Allow S3 to invoke waste_detector when a new file is uploaded
resource "aws_lambda_permission" "s3_invoke_waste_detector" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.waste_detector.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.cost_data.arn
  # source_arn restricts this permission to only our specific S3 bucket
}


# ═══════════════════════════════════════════════════════════════════════════════
# LAMBDA 3: cost_intelligence_api
# Triggered by API Gateway on every HTTP request
# Reads DynamoDB + S3, returns JSON to the React dashboard
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-api"
  description   = "REST API backend — reads findings and trends, serves the React dashboard"

  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256

  runtime = var.lambda_runtime
  handler = "handler.lambda_handler"

  timeout     = 30     # API should respond fast — 30 seconds max
  memory_size = 256

  role = aws_iam_role.api.arn

  environment {
    variables = {
      COST_BUCKET    = var.s3_bucket_name
      DYNAMODB_TABLE = var.dynamodb_table_name
    }
  }
}

# Allow API Gateway to invoke the api Lambda
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.cost_intel.execution_arn}/*/*"
  # /*/*  means: any HTTP method, any route — API Gateway handles the routing
}

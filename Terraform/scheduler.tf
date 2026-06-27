# ============================================================
# scheduler.tf
# EventBridge rule that triggers cost_collector every morning.
# Also includes CloudWatch alarms for operational observability.
# ============================================================


# ── EventBridge Rule — daily schedule ────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "daily_collection" {
  name                = "${var.project_name}-daily-collection"
  description         = "Triggers cost_collector Lambda every morning at 8AM UTC"
  schedule_expression = var.schedule_expression
  # Default: "cron(0 8 * * ? *)" = 8:00 AM UTC every day
  # Cron format: minute hour day-of-month month day-of-week year
  # ? = "any" for day-of-month when day-of-week is specified (AWS quirk)

  state = "ENABLED"   # change to "DISABLED" to pause collection
}

# Connect the EventBridge rule to the cost_collector Lambda
resource "aws_cloudwatch_event_target" "cost_collector" {
  rule      = aws_cloudwatch_event_rule.daily_collection.name
  target_id = "cost-collector-target"
  arn       = aws_lambda_function.cost_collector.arn
  # When the rule fires, it invokes this Lambda ARN
}


# ── CloudWatch Log Groups — one per Lambda ────────────────────────────────────
# Explicitly creating log groups lets us set retention.
# Otherwise AWS creates them automatically with no expiry (logs pile up forever).

resource "aws_cloudwatch_log_group" "cost_collector" {
  name              = "/aws/lambda/${aws_lambda_function.cost_collector.function_name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "waste_detector" {
  name              = "/aws/lambda/${aws_lambda_function.waste_detector.function_name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = 30
}


# ── CloudWatch Alarm: cost_collector errors ────────────────────────────────────
# Fires if cost_collector fails more than once in a day.
# Useful to know if AWS Cost Explorer API is down or IAM permissions broke.

resource "aws_cloudwatch_metric_alarm" "cost_collector_errors" {
  alarm_name          = "${var.project_name}-cost-collector-errors"
  alarm_description   = "cost_collector Lambda is throwing errors"

  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.cost_collector.function_name
  }

  statistic           = "Sum"
  period              = 86400    # 86400 seconds = 24 hours — check once per day
  evaluation_periods  = 1        # alert after 1 period of failure
  threshold           = 1        # alert if errors > 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  # treat_missing_data = "notBreaching" means "no data = no alarm"
  # Important: if the Lambda didn't run (weekend), we don't want false alarms
}


# ── CloudWatch Alarm: waste_detector errors ────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "waste_detector_errors" {
  alarm_name          = "${var.project_name}-waste-detector-errors"
  alarm_description   = "waste_detector Lambda is throwing errors"

  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.waste_detector.function_name
  }

  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}


# ── CloudWatch Alarm: API high error rate ─────────────────────────────────────
# Fires if more than 10% of API requests return errors in a 5-minute window.

resource "aws_cloudwatch_metric_alarm" "api_error_rate" {
  alarm_name          = "${var.project_name}-api-high-error-rate"
  alarm_description   = "API Lambda error rate above 10%"

  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }

  statistic           = "Sum"
  period              = 300    # 5 minutes
  evaluation_periods  = 2      # alert after 2 consecutive 5-min periods
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

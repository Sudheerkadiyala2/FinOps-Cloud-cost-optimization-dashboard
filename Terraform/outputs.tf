# ============================================================
# outputs.tf
# Values printed after "terraform apply" completes.
# These are the things you'll need to configure your app.
# ============================================================

output "api_base_url" {
  description = "The live API Gateway base URL — use this in your React dashboard and docs"
  value       = aws_apigatewayv2_stage.default.invoke_url
  # Example: https://naijpkbw4m.execute-api.us-east-1.amazonaws.com
}

output "api_endpoints" {
  description = "All available API endpoints"
  value = {
    summary  = "${aws_apigatewayv2_stage.default.invoke_url}/summary"
    findings = "${aws_apigatewayv2_stage.default.invoke_url}/findings"
    trends   = "${aws_apigatewayv2_stage.default.invoke_url}/trends"
  }
}

output "s3_bucket_name" {
  description = "S3 bucket storing raw cost data"
  value       = aws_s3_bucket.cost_data.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.cost_data.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table storing waste findings"
  value       = aws_dynamodb_table.cost_waste_findings.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.cost_waste_findings.arn
}

output "cost_collector_function_name" {
  description = "cost_collector Lambda function name"
  value       = aws_lambda_function.cost_collector.function_name
}

output "waste_detector_function_name" {
  description = "waste_detector Lambda function name"
  value       = aws_lambda_function.waste_detector.function_name
}

output "api_function_name" {
  description = "API Lambda function name"
  value       = aws_lambda_function.api.function_name
}

output "eventbridge_rule_name" {
  description = "EventBridge rule triggering the daily collection"
  value       = aws_cloudwatch_event_rule.daily_collection.name
}

output "aws_region" {
  description = "Region everything is deployed in"
  value       = var.aws_region
}

# Useful summary printed after apply
output "deployment_summary" {
  description = "Quick summary of what was deployed"
  value = <<-EOT

    ╔══════════════════════════════════════════════════════╗
    ║   AWS Cost Intelligence Platform — Deployed          ║
    ╠══════════════════════════════════════════════════════╣
    ║  API URL  : ${aws_apigatewayv2_stage.default.invoke_url}
    ║  S3       : ${aws_s3_bucket.cost_data.bucket}
    ║  DynamoDB : ${aws_dynamodb_table.cost_waste_findings.name}
    ║  Schedule : ${var.schedule_expression}
    ╚══════════════════════════════════════════════════════╝

    Test your API:
      curl ${aws_apigatewayv2_stage.default.invoke_url}/summary
      curl ${aws_apigatewayv2_stage.default.invoke_url}/findings
      curl ${aws_apigatewayv2_stage.default.invoke_url}/trends

    Manually trigger collection:
      aws lambda invoke --function-name ${aws_lambda_function.cost_collector.function_name} /tmp/out.json

  EOT
}

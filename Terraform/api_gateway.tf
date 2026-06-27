# ============================================================
# api_gateway.tf
# HTTP API Gateway with 4 routes pointing to the api Lambda.
# HTTP API is cheaper and simpler than REST API for our needs.
# ============================================================


# ── The API itself ────────────────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "cost_intel" {
  name          = "${var.project_name}-api"
  description   = "Cloud Cost Intelligence Platform API"
  protocol_type = "HTTP"   # HTTP API — not REST API (simpler, cheaper)

  # CORS configuration — allows the React dashboard (on any domain) to call this API.
  # Without CORS, browsers block cross-origin API calls.
  cors_configuration {
    allow_origins = ["*"]                    # allow any origin (dashboard on any domain)
    allow_methods = ["GET", "PUT", "OPTIONS"] # the HTTP methods we use
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300    # browser caches CORS preflight for 300 seconds
  }
}


# ── Lambda integration ────────────────────────────────────────────────────────
# One integration connects the API to the Lambda function.
# All 4 routes use this same integration — the Lambda handles routing internally.

resource "aws_apigatewayv2_integration" "api_lambda" {
  api_id             = aws_apigatewayv2_api.cost_intel.id
  integration_type   = "AWS_PROXY"
  # AWS_PROXY = API Gateway passes the full HTTP request to Lambda as-is.
  # Lambda gets the path, method, headers, body — and returns the full response.

  integration_uri    = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
  # 2.0 = newer, simpler event format. The api_handler.py uses event.get('rawPath')
  # which works with payload format 2.0
}


# ── Routes ────────────────────────────────────────────────────────────────────
# Each route maps an HTTP method + path to the Lambda integration.

resource "aws_apigatewayv2_route" "get_summary" {
  api_id    = aws_apigatewayv2_api.cost_intel.id
  route_key = "GET /summary"    # "GET /summary" → Lambda
  target    = "integrations/${aws_apigatewayv2_integration.api_lambda.id}"
}

resource "aws_apigatewayv2_route" "get_findings" {
  api_id    = aws_apigatewayv2_api.cost_intel.id
  route_key = "GET /findings"
  target    = "integrations/${aws_apigatewayv2_integration.api_lambda.id}"
}

resource "aws_apigatewayv2_route" "get_trends" {
  api_id    = aws_apigatewayv2_api.cost_intel.id
  route_key = "GET /trends"
  target    = "integrations/${aws_apigatewayv2_integration.api_lambda.id}"
}

resource "aws_apigatewayv2_route" "put_finding_resolve" {
  api_id    = aws_apigatewayv2_api.cost_intel.id
  route_key = "PUT /findings/{id}"
  # {id} is a path parameter — API Gateway extracts it and passes to Lambda
  target    = "integrations/${aws_apigatewayv2_integration.api_lambda.id}"
}


# ── Stage (deployment) ────────────────────────────────────────────────────────
# A stage is a deployment environment. "$default" means the URL has no stage prefix.
# URL will be: https://abc123.execute-api.us-east-1.amazonaws.com/findings
# (not: https://abc123.execute-api.us-east-1.amazonaws.com/prod/findings)

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.cost_intel.id
  name        = "$default"
  auto_deploy = true
  # auto_deploy = true means every route change deploys automatically.
  # No manual "Deploy API" step needed.

  # Access logs — every API request is logged to CloudWatch
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
  }
}


# ── CloudWatch log group for API Gateway access logs ─────────────────────────

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 30   # keep logs for 30 days then auto-delete
}

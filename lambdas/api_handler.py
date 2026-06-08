# ============================================================
# API LAMBDA — lambdas/api/handler.py
#
# What this file does:
# This Lambda IS your API. API Gateway receives a request from
# the React dashboard, wakes up this Lambda, and this Lambda
# reads from DynamoDB/S3 and sends back JSON.
#
# This Lambda handles 3 endpoints:
#   GET /summary   → total spend, total waste, savings %
#   GET /findings  → list of all waste findings
#   GET /trends    → daily spend data for the chart
#   PUT /findings/{id} → mark a finding as resolved
# ============================================================
#checking whether code change replicates in aws

import json          # converts Python dict → JSON string (to send back to the dashboard)
import boto3         # AWS SDK — to talk to DynamoDB and S3
import os            # to read environment variables
from boto3.dynamodb.conditions import Attr
# Attr lets us filter DynamoDB results
# e.g. Attr('status').eq('open') means "where status = open"
from decimal import Decimal
# DynamoDB stores numbers as Decimal type (not float)
# We need to convert them before putting in JSON


# --- AWS CLIENTS -------------------------------------------
dynamodb = boto3.resource('dynamodb')
s3       = boto3.client('s3')
table    = dynamodb.Table('cost-waste-findings')   # our waste findings table
BUCKET   = os.environ['COST_BUCKET']               # e.g. "sudheer-cost-intelligence"


# --- HELPER: Fix DynamoDB Decimal numbers ------------------
# Problem: DynamoDB returns numbers as Decimal('3.60')
# Problem: json.dumps() cannot handle Decimal — it crashes
# Solution: this function converts Decimal → float before JSON conversion
def decimal_to_float(obj):
    if isinstance(obj, Decimal):   # isinstance checks if obj is a Decimal type
        return float(obj)          # convert to regular Python float
    # If it's not a Decimal, raise an error (json.dumps will handle other types)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")


# --- HELPER: Build HTTP response ---------------------------
# API Gateway expects a specific format back from Lambda.
# It needs: statusCode (like 200 = OK, 404 = not found),
# headers (metadata about the response), and body (the actual data).
# The body MUST be a string — not a dict — so we json.dumps() it.
def respond(status_code, data):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            # This next header is CRITICAL for React dashboards
            # CORS = Cross-Origin Resource Sharing
            # Without it, the browser BLOCKS the response because
            # the API is on a different domain than the React app
            # '*' means "allow requests from any domain" — fine for our project
            'Access-Control-Allow-Origin': '*',
        },
        # json.dumps converts Python dict → JSON string
        # default=decimal_to_float handles the DynamoDB Decimal numbers
        'body': json.dumps(data, default=decimal_to_float)
    }


# --- MAIN LAMBDA HANDLER -----------------------------------
# API Gateway passes the HTTP request as the "event" dict.
# event contains: the path (/findings), the method (GET/PUT),
# path parameters (like the finding ID), query strings, etc.
def lambda_handler(event, context):

    # Read which URL path was called and which HTTP method was used
    path   = event.get('rawPath', '/')          # e.g. "/findings" or "/summary"
    method = event.get('requestContext', {}).get('http', {}).get('method', 'GET')
    # This nested .get() navigates the event structure safely
    # If any key is missing, it returns the default value instead of crashing

    print(f"Received {method} {path}")   # this appears in CloudWatch Logs — useful for debugging


    # --------------------------------------------------------
    # ROUTE: GET /summary
    # Returns: total monthly cost, total waste, savings %, findings count
    # Used by: the summary cards at the top of the dashboard
    # --------------------------------------------------------
    if path == '/summary' and method == 'GET':
        return get_summary()


    # --------------------------------------------------------
    # ROUTE: GET /findings
    # Returns: all waste findings from DynamoDB
    # Used by: the waste findings table on the dashboard
    # Optional: ?status=open filters to only open findings
    # --------------------------------------------------------
    elif path == '/findings' and method == 'GET':
        # Query string parameters come in as a dict
        # e.g. /findings?status=open → {'status': 'open'}
        params = event.get('queryStringParameters') or {}
        status_filter = params.get('status')   # None if not provided
        return get_findings(status_filter)


    # --------------------------------------------------------
    # ROUTE: GET /trends
    # Returns: daily spend for the last 30 days
    # Used by: the daily cost trend line chart
    # --------------------------------------------------------
    elif path == '/trends' and method == 'GET':
        return get_trends()


    # --------------------------------------------------------
    # ROUTE: PUT /findings/{id}
    # Updates a finding's status to "resolved"
    # Used by: when a team fixes a waste issue, they click Resolve
    # --------------------------------------------------------
    elif path.startswith('/findings/') and method == 'PUT':
        # Extract the finding ID from the URL
        # "/findings/vol-0abc123" → split by "/" → ["", "findings", "vol-0abc123"]
        # [-1] gets the last element → "vol-0abc123"
        resource_id = path.split('/')[-1]
        return resolve_finding(resource_id, event)


    # --------------------------------------------------------
    # ROUTE: OPTIONS /* (CORS preflight)
    # Browsers send an OPTIONS request before every real request
    # to check if the API allows cross-origin calls.
    # We just return 200 with the CORS headers and an empty body.
    # --------------------------------------------------------
    elif method == 'OPTIONS':
        return respond(200, {})


    # If no route matched, return 404
    else:
        return respond(404, {'error': f'Route not found: {method} {path}'})


# ============================================================
# FUNCTION: get_summary()
# Reads all findings, computes totals, returns summary numbers
# ============================================================
def get_summary():
    # Scan the entire DynamoDB table (fine at our scale — hundreds of items max)
    response = table.scan()
    all_findings = response.get('Items', [])   # .get() returns [] if 'Items' key missing

    # Separate open vs resolved findings
    open_findings     = [f for f in all_findings if f.get('status') == 'open']
    resolved_findings = [f for f in all_findings if f.get('status') == 'resolved']

    # Calculate total estimated waste from open findings
    # float() converts Decimal or string to number
    # sum() adds them all up
    total_waste = sum(
        float(f.get('estimatedMonthlySavings', 0))
        for f in open_findings
    )

    # Calculate total savings realised from resolved findings
    total_saved = sum(
        float(f.get('estimatedMonthlySavings', 0))
        for f in resolved_findings
    )

    # Group open findings by waste type — for the "findings by category" chart
    by_type = {}
    for f in open_findings:
        waste_type = f.get('wasteType', 'unknown')
        # setdefault creates the key with value 0 if it doesn't exist yet
        by_type.setdefault(waste_type, {'count': 0, 'totalSavings': 0.0})
        by_type[waste_type]['count'] += 1
        by_type[waste_type]['totalSavings'] += float(f.get('estimatedMonthlySavings', 0))

    return respond(200, {
        'openFindingsCount':     len(open_findings),
        'resolvedFindingsCount': len(resolved_findings),
        'totalEstimatedWaste':   round(total_waste, 2),   # round to 2 decimal places
        'totalSavingsRealised':  round(total_saved, 2),
        'findingsByType':        by_type,
    })


# ============================================================
# FUNCTION: get_findings()
# Returns the list of waste findings, optionally filtered by status
# ============================================================
def get_findings(status_filter=None):

    if status_filter:
        # If a status filter was provided, only return matching findings
        # Attr('status').eq(status_filter) is DynamoDB's way of saying "WHERE status = ?"
        response = table.scan(
            FilterExpression=Attr('status').eq(status_filter)
        )
    else:
        # No filter — return everything
        response = table.scan()

    findings = response.get('Items', [])

    # Sort by estimatedMonthlySavings descending
    # So the biggest waste appears at the top of the dashboard table
    findings.sort(
        key=lambda f: float(f.get('estimatedMonthlySavings', 0)),
        reverse=True   # True = descending (highest first)
    )

    return respond(200, {
        'findings': findings,
        'count':    len(findings),
    })


# ============================================================
# FUNCTION: get_trends()
# Reads the latest cost data file from S3 and returns daily spend
# ============================================================
def get_trends():
    from datetime import date, timedelta

    # Try to find the most recent cost data file
    # We check today first, then yesterday (in case today's hasn't run yet)
    today     = date.today()
    yesterday = today - timedelta(days=1)

    cost_data = None
    latest_key = None
    for target_date in [today, yesterday]:
        date_prefix = f"raw-data/{target_date.strftime('%Y-%m-%d')}"
        # strftime('%Y-%m-%d') → "2026-06-08"

        # List all objects under this date prefix
        response = s3.list_objects_v2(Bucket=BUCKET, Prefix=date_prefix)
        objects  = response.get('Contents', [])
        # 'Contents' is a list of dicts — each has 'Key', 'LastModified', 'Size', etc.

        if not objects:
            # No files for this date — try yesterday
            continue

        # Sort by LastModified descending — pick the most recent file for that day
        objects.sort(key=lambda x: x['LastModified'], reverse=True)
        latest_key = objects[0]['Key']
        # e.g. "raw-data/2026-06-08-01-00-50.json"

        # ---  Read the file ---
        obj       = s3.get_object(Bucket=BUCKET, Key=latest_key)
        cost_data = json.loads(obj['Body'].read().decode('utf-8'))
        break  # found a file — stop looping 


    if not cost_data:
        # No data found for today or yesterday
        return respond(404, {'error': 'No cost data available yet. Cost collector may not have run.'})

    # Extract just the daily trend data — list of {date, spend} objects
    daily_trend = []
    for day_record in cost_data.get('dailyTrend', []):
        # day_record looks like:
        # { "TimePeriod": {"Start": "2025-06-04"}, "Total": {"UnblendedCost": {"Amount": "27.10"}} }
        daily_trend.append({
            'date':  day_record['TimePeriod']['Start'],   # e.g. "2025-06-04"
            'spend': round(float(day_record['Total']['UnblendedCost']['Amount']), 2)
        })

    # Extract cost by service — for the "spend by service" bar chart
    service_costs = []
    for result in cost_data.get('byService', []):
        for group in result.get('Groups', []):
            service_costs.append({
                'service': group['Keys'][0],   # e.g. "Amazon EC2"
                'cost':    round(float(group['Metrics']['UnblendedCost']['Amount']), 2)
            })

    # Sort services by cost descending — biggest spender first
    service_costs.sort(key=lambda x: x['cost'], reverse=True)

    return respond(200, {
        'dailyTrend':   daily_trend,
        'byService':    service_costs[:10],   # top 10 services only
        'collectedAt':  cost_data.get('collectedAt'),
        'sourceFile' :  latest_key,
    })


# ============================================================
# FUNCTION: resolve_finding()
# Updates a finding's status from "open" to "resolved"
# Called when someone on the team fixes the waste issue
# ============================================================
def resolve_finding(resource_id, event):
    from datetime import datetime, timezone

    if not resource_id:
        return respond(400, {'error': 'resource_id is required'})
        # 400 = Bad Request — the caller did something wrong

    # We also need the timestamp (sort key) to identify the exact record
    # The frontend should send it in the request body
    body = {}
    if event.get('body'):
        # event['body'] is a string — we parse it as JSON
        body = json.loads(event['body'])

    timestamp = body.get('timestamp')
    if not timestamp:
        return respond(400, {'error': 'timestamp is required in request body'})

    # Update the item in DynamoDB
    # UpdateExpression = what fields to change
    # ExpressionAttributeValues = the new values (prefixed with :)
    table.update_item(
        Key={
            'resourceId': resource_id,   # partition key
            'timestamp':  timestamp,     # sort key
        },
        UpdateExpression='SET #s = :status, resolvedAt = :resolvedAt',
        # #s is an alias for "status" — "status" is a reserved word in DynamoDB
        # so we use an alias to avoid conflicts
        ExpressionAttributeNames={'#s': 'status'},
        ExpressionAttributeValues={
            ':status':     'resolved',
            ':resolvedAt': datetime.now(timezone.utc).isoformat(),
        }
    )

    return respond(200, {
        'message':    f'Finding {resource_id} marked as resolved',
        'resourceId': resource_id,
    })

# ============================================================
# storage.tf
# S3 bucket for raw cost data + DynamoDB findings table.
# These are the two persistence layers of the platform.
# ============================================================


# ── S3 Bucket ────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "cost_data" {
  bucket = var.s3_bucket_name
  # S3 bucket names must be globally unique across ALL AWS accounts.
  # If this name is taken, change s3_bucket_name in variables.tf

  # prevent_destroy = true would stop accidental deletion
  # Leaving it off so you can destroy cleanly during development
}

# Block all public access — this bucket should never be public
resource "aws_s3_bucket_public_access_block" "cost_data" {
  bucket = aws_s3_bucket.cost_data.id

  block_public_acls       = true   # block public ACLs
  block_public_policy     = true   # block public bucket policies
  ignore_public_acls      = true   # ignore existing public ACLs
  restrict_public_buckets = true   # restrict public bucket access
}

# Enable versioning — lets you recover from accidental overwrites
resource "aws_s3_bucket_versioning" "cost_data" {
  bucket = aws_s3_bucket.cost_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rule — automatically delete old cost data after 90 days
# Keeps S3 costs near zero while retaining 3 months of history
resource "aws_s3_bucket_lifecycle_configuration" "cost_data" {
  bucket = aws_s3_bucket.cost_data.id

  rule {
    id     = "expire-old-cost-data"
    status = "Enabled"

    # Apply to everything under cost-data/
    filter {
      prefix = "cost-data/"
    }

    expiration {
      days = 90   # delete files older than 90 days
    }

    # Also delete old versions to save space
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# S3 event notification — triggers waste_detector Lambda when
# cost_collector uploads a new file. This closes the pipeline loop.
resource "aws_s3_bucket_notification" "trigger_waste_detector" {
  bucket = aws_s3_bucket.cost_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.waste_detector.arn

    # Only trigger when a new file is created (not updated or deleted)
    events = ["s3:ObjectCreated:*"]

    # Only trigger for files uploaded under raw-data/ prefix
    filter_prefix = "raw-data/"

    # Only trigger for .json files
    filter_suffix = ".json"
  }

  # Terraform needs to create the Lambda permission before setting
  # up the notification, otherwise AWS will reject it
  depends_on = [aws_lambda_permission.s3_invoke_waste_detector]
}


# ── DynamoDB Table ────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "cost_waste_findings" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"   # no capacity planning needed — pay per read/write

  # Primary key structure:
  # Partition key = resourceId (the AWS resource ID, e.g. "i-0abc123")
  # Sort key      = timestamp  (when the finding was detected)
  # Together they make every finding record unique
  hash_key  = "resourceId"    # partition key
  range_key = "timestamp"     # sort key

  attribute {
    name = "resourceId"
    type = "S"   # S = String
  }

  attribute {
    name = "timestamp"
    type = "S"   # S = String (ISO 8601 format)
  }

  # TTL = Time To Live
  # DynamoDB will automatically delete findings older than the expiresAt value
  # This keeps the table lean without any manual cleanup
  ttl {
    attribute_name = "expiresAt"   # Lambda sets this field when writing
    enabled        = true
  }

  # Point-in-time recovery — lets you restore the table to any point
  # in the last 35 days. Protects against accidental bulk deletes.
  point_in_time_recovery {
    enabled = true
  }

  # Global Secondary Index — lets us query findings by status
  # e.g. "give me all open findings" without scanning the whole table
  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    projection_type = "ALL"   # include all attributes in the index
  }

  # We need to declare the status attribute since it's used in a GSI
  attribute {
    name = "status"
    type = "S"
  }
}

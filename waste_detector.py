# ============================================================
# WASTE DETECTOR LAMBDA
# What this file does: Every day after the cost collector runs,
# this Lambda looks at all your running AWS resources and asks
# "is anyone paying for something they're not using?"
# It finds 3 types of waste and writes each finding to DynamoDB.
# ============================================================


# --- IMPORTS ------------------------------------------------
import boto3         # AWS library for Python
import json          # for converting data to JSON if needed
import os            # for reading environment variables
from datetime import datetime, timedelta, timezone
# datetime  → working with dates and times
# timedelta → date maths (e.g. "14 days ago")
# timezone  → always work in UTC


# --- AWS CLIENTS --------------------------------------------
ec2      = boto3.client('ec2')          # EC2 — manages virtual machines (instances), volumes, IPs
cw       = boto3.client('cloudwatch')   # CloudWatch — has CPU/memory metrics for each instance
dynamodb = boto3.resource('dynamodb')   # DynamoDB — our database for storing waste findings
                                        # Note: .resource() gives a higher-level interface than .client()
                                        # easier for reading/writing individual items

# Get the DynamoDB table object — this is the table we'll write findings into
table = dynamodb.Table('cost-waste-findings')


# --- INSTANCE PRICING REFERENCE -----------------------------
# AWS doesn't give us instance prices via API easily.
# We maintain a simple lookup dictionary: instance type → hourly price (USD)
# Source: https://aws.amazon.com/ec2/pricing/on-demand/ (ap-south-1 Mumbai region)
# Add more instance types as you encounter them in your account
EC2_HOURLY_PRICE = {
    't2.micro':   0.0116,
    't2.small':   0.023,
    't2.medium':  0.0464,
    't3.micro':   0.0104,
    't3.small':   0.0208,
    't3.medium':  0.0416,
    't3.large':   0.0832,
    'm5.large':   0.096,
    'm5.xlarge':  0.192,
    'm5.2xlarge': 0.384,
    'r5.large':   0.126,
    'r5.xlarge':  0.252,
    'r5.2xlarge': 0.504,
}

# Default price if the instance type isn't in our list
# $0.10/hr is a safe middle-ground estimate
DEFAULT_HOURLY_PRICE = 0.10


# --- MAIN FUNCTION ------------------------------------------
def lambda_handler(event, context):

    # We'll collect all findings from all 3 checks into this list
    all_findings = []

    # Run all 3 waste checks and add results to the list
    all_findings += find_idle_ec2()        # check 1: EC2 instances that are barely used
    all_findings += find_unused_eips()     # check 2: Elastic IPs not attached to anything
    all_findings += find_unattached_ebs()  # check 3: storage volumes floating with no instance

    # Save every finding to DynamoDB
    saved_count = 0
    for finding in all_findings:
        table.put_item(Item={
            **finding,                                         # spread all keys from the finding dict
            'detectedAt': datetime.now(timezone.utc).isoformat(),  # timestamp when we found it
            'status':     'open',                             # open = not yet resolved
        })
        saved_count += 1

    print(f"Waste detector complete. Found and stored {saved_count} findings.")
    return {'statusCode': 200, 'findingsCount': saved_count}


# ============================================================
# WASTE CHECK 1: IDLE EC2 INSTANCES
# Definition: a running EC2 instance with average CPU < 5%
# over the last 14 days. It's running but doing nothing.
# Waste = you're paying full price for an idle server.
# ============================================================
def find_idle_ec2():
    findings = []   # will hold all idle EC2 findings

    # Get all currently RUNNING EC2 instances
    # Filters let us ask for only instances in a specific state
    response = ec2.describe_instances(
        Filters=[{
            'Name':   'instance-state-name',  # filter by current state
            'Values': ['running']              # only "running" — skip stopped/terminated
        }]
    )

    # "14 days ago" — our lookback window for CPU data
    # timezone.utc makes it timezone-aware (required by CloudWatch API)
    fourteen_days_ago = datetime.now(timezone.utc) - timedelta(days=14)
    now               = datetime.now(timezone.utc)

    # EC2 results come back in "Reservations" — each Reservation can have
    # multiple Instances. It's just how the AWS API groups them.
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:

            instance_id   = instance['InstanceId']    # e.g. "i-0abc123def456"
            instance_type = instance['InstanceType']  # e.g. "t3.medium"

            # ------------------------------------------------
            # Get 14 days of CPU data for this instance
            # We ask for daily average CPU so we get 14 data points
            # ------------------------------------------------
            cpu_data = cw.get_metric_statistics(
                Namespace='AWS/EC2',                         # built-in EC2 metrics namespace
                MetricName='CPUUtilization',                 # the metric we want
                Dimensions=[{
                    'Name':  'InstanceId',                   # filter to one specific instance
                    'Value': instance_id
                }],
                StartTime=fourteen_days_ago,                 # from 14 days ago
                EndTime=now,                                 # to now
                Period=86400,                                # 86400 seconds = 1 day
                                                             # so we get one average per day
                Statistics=['Average']                       # we want the average, not max/min
            )

            # If there are no datapoints, the instance might be too new
            # or CloudWatch hasn't collected data yet — skip it
            if not cpu_data['Datapoints']:
                continue   # "continue" skips to the next loop iteration

            # Calculate the overall average CPU across all 14 days
            # sum() adds up all the Average values, len() counts the datapoints
            avg_cpu = (
                sum(point['Average'] for point in cpu_data['Datapoints'])
                / len(cpu_data['Datapoints'])
            )

            # If average CPU is below 5%, this instance is idle
            if avg_cpu < 5.0:

                # Look up the hourly price for this instance type
                # .get() returns DEFAULT_HOURLY_PRICE if the type isn't in our dict
                hourly_price  = EC2_HOURLY_PRICE.get(instance_type, DEFAULT_HOURLY_PRICE)
                monthly_cost  = round(hourly_price * 24 * 30, 2)  # 24 hrs × 30 days

                # Extract the "Name" tag from the instance (if it exists)
                # Tags are a list of {'Key': ..., 'Value': ...} dicts
                # next() finds the first tag where Key == 'Name', returns instance_id if not found
                name_tag = next(
                    (t['Value'] for t in instance.get('Tags', []) if t['Key'] == 'Name'),
                    instance_id   # fallback: use instance ID if no Name tag
                )

                # Extract the "Team" tag to know which team owns this resource
                owner_tag = next(
                    (t['Value'] for t in instance.get('Tags', []) if t['Key'] == 'Team'),
                    'unknown'   # fallback: if no Team tag, owner is unknown
                )

                # Build the finding dict and add it to our list
                findings.append({
                    'resourceId':              instance_id,
                    'resourceName':            name_tag,
                    'resourceType':            'EC2 Instance',
                    'wasteType':               'idle-ec2',
                    'detail':                  f'{instance_type}, avg CPU {avg_cpu:.1f}% over 14 days',
                    # :.1f means "show 1 decimal place" — so 2.3456 becomes "2.3"
                    'estimatedMonthlySavings': str(monthly_cost),   # stored as string in DynamoDB
                    'ownerTag':                owner_tag,
                    'region':                  os.environ.get('AWS_REGION', 'ap-south-1'),
                })

    return findings


# ============================================================
# WASTE CHECK 2: UNUSED ELASTIC IPs
# Definition: an Elastic IP that is not attached to any EC2
# instance or network interface.
# Waste: AWS charges $3.60/month for every unattached EIP.
# It's a small amount but they add up fast and are easy to miss.
# ============================================================
def find_unused_eips():
    findings = []

    # Get ALL Elastic IPs in this account/region
    response = ec2.describe_addresses()

    for eip in response['Addresses']:

        # If AssociationId exists, the EIP is attached to something — skip it
        # If AssociationId is MISSING, the EIP is floating free — that's waste
        if 'AssociationId' not in eip:

            findings.append({
                'resourceId':              eip.get('AllocationId', eip['PublicIp']),
                # AllocationId is the internal ID (e.g. "eipalloc-0abc123")
                # PublicIp is the actual IP address (e.g. "52.66.142.11")
                # We prefer AllocationId, fall back to PublicIp

                'resourceName':            eip['PublicIp'],   # show the human-readable IP
                'resourceType':            'Elastic IP',
                'wasteType':               'unused-eip',
                'detail':                  'Elastic IP not associated with any resource',
                'estimatedMonthlySavings': '3.60',            # AWS fixed charge per unused EIP
                'ownerTag':                'unknown',          # EIPs rarely have team tags
                'region':                  os.environ.get('AWS_REGION', 'ap-south-1'),
            })

    return findings


# ============================================================
# WASTE CHECK 3: UNATTACHED EBS VOLUMES
# Definition: an EBS volume (storage disk) that is not attached
# to any EC2 instance. This happens when you delete an EC2
# instance but forget to delete its disk.
# Waste: you pay for storage that no instance is using.
# Cost: gp2 = $0.10/GB/month, gp3 = $0.08/GB/month
# ============================================================
def find_unattached_ebs():
    findings = []

    # Get all EBS volumes where state = 'available'
    # "available" means not attached to any instance
    # (contrast with "in-use" = attached, "creating", "deleting", "deleted", "error")
    response = ec2.describe_volumes(
        Filters=[{
            'Name':   'status',
            'Values': ['available']   # only unattached volumes
        }]
    )

    for volume in response['Volumes']:

        volume_id   = volume['VolumeId']     # e.g. "vol-0abc123def"
        size_gb     = volume['Size']          # size in GB, e.g. 500
        volume_type = volume['VolumeType']   # e.g. "gp2", "gp3", "io1"

        # Calculate monthly cost based on volume type
        # Different volume types have different per-GB prices
        price_per_gb = {
            'gp2': 0.10,    # general purpose SSD (older)
            'gp3': 0.08,    # general purpose SSD (newer, cheaper)
            'io1': 0.125,   # provisioned IOPS SSD (expensive)
            'io2': 0.125,
            'st1': 0.045,   # throughput optimised HDD
            'sc1': 0.025,   # cold HDD (cheapest)
        }.get(volume_type, 0.10)   # default to $0.10 if unknown type

        monthly_cost = round(size_gb * price_per_gb, 2)   # e.g. 500 GB × $0.10 = $50.00

        # Get the Name tag if it exists
        name_tag = next(
            (t['Value'] for t in volume.get('Tags', []) if t['Key'] == 'Name'),
            volume_id   # fallback to volume ID
        )

        # Get the Team tag
        owner_tag = next(
            (t['Value'] for t in volume.get('Tags', []) if t['Key'] == 'Team'),
            'unknown'
        )

        # Format the date the volume was created — tells us how long it's been floating
        # CreateTime is a datetime object, .strftime() formats it as a readable string
        created_date = volume['CreateTime'].strftime('%Y-%m-%d')

        findings.append({
            'resourceId':              volume_id,
            'resourceName':            name_tag,
            'resourceType':            'EBS Volume',
            'wasteType':               'unattached-ebs',
            'detail':                  f'{size_gb}GB {volume_type} volume, unattached since {created_date}',
            'estimatedMonthlySavings': str(monthly_cost),
            'ownerTag':                owner_tag,
            'region':                  os.environ.get('AWS_REGION', 'ap-south-1'),
        })

    return findings
# ============================================================
# COST COLLECTOR LAMBDA
# What this file does:
# Every day this Lambda collects AWS infrastructure data
# from the account and stores it for later analysis.
#
# The waste detector will later use this collected data
# to identify cloud cost wastage.
#
# Resources collected:
# 1. EC2 instances
# 2. Elastic IPs
# 3. EBS volumes
# ============================================================


# --- IMPORTS ------------------------------------------------
import boto3
import json
import os

from datetime import datetime, timedelta, timezone


# --- AWS CLIENTS --------------------------------------------
# EC2 → instances, EBS volumes, Elastic IPs
# CloudWatch → CPU/network metrics
# S3 → store collected raw data

ec2 = boto3.client('ec2')

cw = boto3.client('cloudwatch')

s3 = boto3.client('s3')


# --- ENVIRONMENT VARIABLES ---------------------------------
# S3 bucket where collected data will be stored

S3_BUCKET = os.environ.get('S3_BUCKET_NAME')


# ============================================================
# MAIN FUNCTION
# ============================================================
def lambda_handler(event, context):

    print("Starting AWS resource collection...")

    # Collect all AWS resources
    ec2_instances = collect_ec2_instances()

    elastic_ips = collect_elastic_ips()

    ebs_volumes = collect_ebs_volumes()

    # Final payload structure
    payload = {
        'generatedAt': datetime.now(timezone.utc).isoformat(),

        'ec2_instances': ec2_instances,

        'elastic_ips': elastic_ips,

        'ebs_volumes': ebs_volumes
    }

    # Create timestamped filename
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%d-%H-%M-%S')

    s3_key = f'raw-data/{timestamp}.json'

    # Store collected data in S3
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=s3_key,
        Body=json.dumps(payload, default=str),
        ContentType='application/json'
    )

    print(f"Collection complete. Uploaded to S3: {s3_key}")

    return {
        'statusCode': 200,
        'message': 'Resource collection completed successfully',
        's3Key': s3_key,
        'ec2Count': len(ec2_instances),
        'elasticIpCount': len(elastic_ips),
        'ebsVolumeCount': len(ebs_volumes)
    }


# ============================================================
# RESOURCE COLLECTION 1: EC2 INSTANCES
#
# What we collect:
# - instance details
# - CPU utilization
# - network traffic
# - tags
#
# Why?
# Waste detector uses this data later to identify:
# - idle instances
# - low utilization
# - missing ownership tags
# ============================================================
def collect_ec2_instances():

    collected_instances = []

    # Get all EC2 instances
    response = ec2.describe_instances()

    # Last 14 days for metrics
    fourteen_days_ago = datetime.now(timezone.utc) - timedelta(days=14)

    now = datetime.now(timezone.utc)

    for reservation in response['Reservations']:

        for instance in reservation['Instances']:

            instance_id = instance['InstanceId']

            instance_type = instance['InstanceType']

            print(f"Collecting metrics for {instance_id}")

            # ------------------------------------------------
            # CPU UTILIZATION
            # ------------------------------------------------
            cpu_response = cw.get_metric_statistics(
                Namespace='AWS/EC2',

                MetricName='CPUUtilization',

                Dimensions=[{
                    'Name': 'InstanceId',
                    'Value': instance_id
                }],

                StartTime=fourteen_days_ago,

                EndTime=now,

                Period=86400,

                Statistics=['Average']
            )

            cpu_datapoints = cpu_response['Datapoints']

            if cpu_datapoints:

                avg_cpu = (
                    sum(point['Average'] for point in cpu_datapoints)
                    / len(cpu_datapoints)
                )

            else:
                avg_cpu = 0


            # ------------------------------------------------
            # NETWORK IN
            # ------------------------------------------------
            network_in_response = cw.get_metric_statistics(
                Namespace='AWS/EC2',

                MetricName='NetworkIn',

                Dimensions=[{
                    'Name': 'InstanceId',
                    'Value': instance_id
                }],

                StartTime=fourteen_days_ago,

                EndTime=now,

                Period=86400,

                Statistics=['Average']
            )

            network_in_points = network_in_response['Datapoints']

            if network_in_points:

                avg_network_in = (
                    sum(point['Average'] for point in network_in_points)
                    / len(network_in_points)
                )

            else:
                avg_network_in = 0


            # ------------------------------------------------
            # NETWORK OUT
            # ------------------------------------------------
            network_out_response = cw.get_metric_statistics(
                Namespace='AWS/EC2',

                MetricName='NetworkOut',

                Dimensions=[{
                    'Name': 'InstanceId',
                    'Value': instance_id
                }],

                StartTime=fourteen_days_ago,

                EndTime=now,

                Period=86400,

                Statistics=['Average']
            )

            network_out_points = network_out_response['Datapoints']

            if network_out_points:

                avg_network_out = (
                    sum(point['Average'] for point in network_out_points)
                    / len(network_out_points)
                )

            else:
                avg_network_out = 0


            # ------------------------------------------------
            # TAG EXTRACTION
            # ------------------------------------------------
            tags = {
                tag['Key']: tag['Value']
                for tag in instance.get('Tags', [])
            }


            # ------------------------------------------------
            # BUILD INSTANCE OBJECT
            # ------------------------------------------------
            collected_instances.append({

                'instance_id': instance_id,

                'instance_type': instance_type,

                'state': instance['State']['Name'],

                'launch_time': instance['LaunchTime'].isoformat(),

                'cpu_avg': round(avg_cpu, 2),

                'network_in': round(avg_network_in, 2),

                'network_out': round(avg_network_out, 2),

                'tags': tags
            })

    return collected_instances


# ============================================================
# RESOURCE COLLECTION 2: ELASTIC IPS
#
# Why?
# Waste detector later checks which Elastic IPs are
# unattached and wasting money.
# ============================================================
def collect_elastic_ips():

    collected_eips = []

    response = ec2.describe_addresses()

    for eip in response['Addresses']:

        collected_eips.append({

            'allocation_id': eip.get(
                'AllocationId',
                eip['PublicIp']
            ),

            'public_ip': eip['PublicIp'],

            # If AssociationId exists → attached
            'associated': 'AssociationId' in eip
        })

    return collected_eips


# ============================================================
# RESOURCE COLLECTION 3: EBS VOLUMES
#
# Why?
# Waste detector later identifies unattached storage
# volumes that are still charging money.
# ============================================================
def collect_ebs_volumes():

    collected_volumes = []

    response = ec2.describe_volumes()

    for volume in response['Volumes']:

        collected_volumes.append({

            'volume_id': volume['VolumeId'],

            'size_gb': volume['Size'],

            'volume_type': volume['VolumeType'],

            'state': volume['State'],

            'create_time': volume['CreateTime'].isoformat(),

            'attached': len(volume['Attachments']) > 0,

            'tags': {
                tag['Key']: tag['Value']
                for tag in volume.get('Tags', [])
            }
        })

    return collected_volumes
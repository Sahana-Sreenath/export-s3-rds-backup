import os
import json
import boto3
from datetime import datetime

def get_db_snapshot():
    """
    Function to get the latest automated snapshot
    Returns: Latest snapshot ARN, or None if no snapshots are available
    """
    db_instance_id = os.environ["DB_INSTANCE_ID"]
    client = boto3.client("rds")
    desc_snapshots = client.describe_db_snapshots(DBInstanceIdentifier=db_instance_id, SnapshotType="automated")
    snapshots = desc_snapshots["DBSnapshots"]
    
    if not snapshots:
        return None
    
    most_recent_snapshot = max(snapshots, key=lambda x: x["SnapshotCreateTime"])
    return most_recent_snapshot["DBSnapshotArn"]

def jsondatetimeconverter(ts):
	"""
	To avoid typeError: datetime.datetime() is not JSON serializable
	"""
	if isinstance(ts, datetime):
		return ts.__str__()

def lambda_handler(event, context):
    """
    Function to invoke start_export_task using recent snapshot
    Return: Response
    """
    s3_bucket = os.environ["S3_BUCKET"]
    iam_role = os.environ["IAM_ROLE"]
    kms_key = os.environ["KMS_KEY"]
    client = boto3.client("rds")

    latest_snapshot_arn = get_db_snapshot()
    if not latest_snapshot_arn:
        return "Export task not started as no snapshots are available"
    
    today_date = datetime.today().strftime("%Y%m%d")
    export_task = f"db-backup-{os.environ['DB_INSTANCE_ID']}-{today_date}"
    
    response = client.start_export_task(
        ExportTaskIdentifier=export_task,
        SourceArn=latest_snapshot_arn,
        S3BucketName=s3_bucket,
        IamRoleArn=iam_role,
        KmsKeyId=kms_key
    )
    
    return json.dumps(response, default=jsondatetimeconverter)

import boto3
import os
from datetime import datetime
import urllib3
import json 

http = urllib3.PoolManager()
rds_client = boto3.client('rds')
sns_client = boto3.client('sns')

db_instance_id = os.environ['DB_INSTANCE_ID']
slack_url = os.environ['SLACK_URL']

def jsondatetimeconverter(ts):
    """
    To avoid typeError: datetime.datetime() is not JSON serializable
    """
    if isinstance(ts, datetime):
        return ts.__str__()

def lambda_handler(event, context):
    try:
        today_date = datetime.today().strftime("%Y%m%d")
        export_task_identifier = f"db-backup-{os.environ['DB_INSTANCE_ID']}-{today_date}"
        response = rds_client.describe_export_tasks(ExportTaskIdentifier=export_task_identifier)
        export_task_arn = response['ExportTasks'][0]['SourceArn']
        export_task_status = response['ExportTasks'][0]['Status']

        if export_task_status in ['STARTING', 'IN_PROGRESS']:
            return {"export_task_status": export_task_status}

        elif export_task_status == 'COMPLETE':
            message = f"The RDS snapshot export task has completed successfully. Export Task Details: {export_task_identifier}"
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=message
            )
            url = slack_url
            msg = {
                "channel": "#cloud-alerts",
                "username": "[OK] DB-RDS-Backup",
                "icon_emoji": "",
                "attachments": [
                    {
                        "color": "#00FF00",
                        "text": message
                    }
                    
                ]
            }

            encoded_msg = json.dumps(msg).encode("utf-8")
            resp = http.request("POST", url, body=encoded_msg)
            print(
                {
                    "message": message,
                    "status_code": resp.status,
                    "response": resp.data,
                }
            )
            return {"export_task_status": export_task_status}

        else:
            # Send SNS notification
            message = f"The RDS snapshot export task has status {export_task_status}. Export Task Details: {export_task_identifier}"
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=message
            )
            url = slack_url
            msg = {
                "channel": "#cloud-alerts",
                "username": "[FAILED] DB-RDS-Backup",
                "icon_emoji": "",
                "attachments": [
                    {
                        "color": "#FF0000",
                        "text": message
                    }
                ]
            }

            encoded_msg = json.dumps(msg).encode("utf-8")
            resp = http.request("POST", url, body=encoded_msg)
            print(
                {
                    "message": message,
                    "status_code": resp.status,
                    "response": resp.data,
                }
            )

    except Exception as e:
        # Send SNS notification
        message = f"Error occurred while checking the RDS snapshot export task for DB instance {db_instance_id}. Error message: {str(e)}. Export Task Details: {export_task_identifier}"
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message
        )
        url = slack_url
        msg = {
            "channel": "#cloud-alerts",
            "username": "[FAILED] DB-RDS-Backup",
            "icon_emoji": "",
            "attachments": [
                {
                    "color": "#FF0000",
                    "text": message
                }
            ]
        }

        encoded_msg = json.dumps(msg).encode("utf-8")
        resp = http.request("POST", url, body=encoded_msg)
        print(
            {
                "message": message,
                "status_code": resp.status,
                "response": resp.data,
            }
        )
        raise e

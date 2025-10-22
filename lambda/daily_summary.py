import boto3
import csv
import io
from datetime import date

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('Employees')
s3 = boto3.client('s3')
sns = boto3.client('sns')

REPORT_BUCKET = 'employee-summary-reports-bucket'  # overwritten by env var
SNS_TOPIC_ARN = 'SNS_TOPIC_ARN_PLACEHOLDER'        # overwritten by env var

def lambda_handler(event, context):
    response = table.scan()
    items = response['Items']

    dept_summary = {}
    for item in items:
        dept = item['department']
        salary = int(item['salary'])
        if dept not in dept_summary:
            dept_summary[dept] = {'count': 0, 'total_salary': 0}
        dept_summary[dept]['count'] += 1
        dept_summary[dept]['total_salary'] += salary

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Department', 'EmployeeCount', 'TotalSalary', 'AverageSalary'])
    for dept, data in dept_summary.items():
        avg = data['total_salary'] / data['count']
        writer.writerow([dept, data['count'], data['total_salary'], round(avg, 2)])

    report_key = f"daily_summary_{date.today()}.csv"
    s3.put_object(Bucket=REPORT_BUCKET, Key=report_key, Body=output.getvalue())

    # Send SNS notification
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="Daily Employee Summary Generated",
        Message=f"Summary report generated and saved to {REPORT_BUCKET}/{report_key}"
    )

    return {"status": "success", "report_key": report_key}
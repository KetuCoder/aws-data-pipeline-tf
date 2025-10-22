import boto3
import csv
import io

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('Employees')

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']

    response = s3.get_object(Bucket=bucket, Key=key)
    content = response['Body'].read().decode('utf-8')
    reader = csv.DictReader(io.StringIO(content))

    for row in reader:
        table.put_item(Item={
            'employee_id': row['employee_id'],
            'name': row['name'],
            'department': row['department'],
            'salary': int(row['salary'])
        })

    print("Data loaded successfully into DynamoDB")
output "s3_data_bucket" {
  value = aws_s3_bucket.data_ingestion.bucket
}

output "s3_report_bucket" {
  value = aws_s3_bucket.summary_reports.bucket
}

output "dynamodb_table" {
  value = aws_dynamodb_table.employees.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.daily_report_notifications.arn
}

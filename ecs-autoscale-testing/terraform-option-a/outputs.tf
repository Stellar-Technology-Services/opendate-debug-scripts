output "resource_id" {
  description = "Application Auto Scaling resource id for the ECS service."
  value       = local.resource_id
}

output "scaling_policy_name" {
  value = aws_appautoscaling_policy.target_tracking.name
}

output "scaling_policy_arn" {
  value = aws_appautoscaling_policy.target_tracking.arn
}

# =============================================================================
# Alerting Outputs
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for scaling notifications."
  value       = aws_sns_topic.scaling_notifications.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule capturing scaling events."
  value       = aws_cloudwatch_event_rule.ecs_service_action.arn
}

output "notification_email" {
  description = "Email address subscribed to scaling notifications."
  value       = var.notification_email
}



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



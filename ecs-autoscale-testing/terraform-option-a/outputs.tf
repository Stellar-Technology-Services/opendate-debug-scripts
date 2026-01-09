output "resource_id" {
  description = "Application Auto Scaling resource id for the ECS service."
  value       = aws_appautoscaling_target.ecs_desired_count.resource_id
}

output "scalable_target_min_capacity" {
  value = aws_appautoscaling_target.ecs_desired_count.min_capacity
}

output "scalable_target_max_capacity" {
  value = aws_appautoscaling_target.ecs_desired_count.max_capacity
}

output "scaling_policy_name" {
  value = aws_appautoscaling_policy.target_tracking.name
}

output "scaling_policy_arn" {
  value = aws_appautoscaling_policy.target_tracking.arn
}



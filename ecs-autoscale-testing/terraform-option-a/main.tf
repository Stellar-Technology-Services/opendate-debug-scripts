locals {
  resource_id = "service/${var.ecs_cluster}/${var.ecs_service}"
}

# NOTE: This assumes a scalable target already exists for the ECS service.
# The policy will attach to the existing target without modifying min/max capacity.
resource "aws_appautoscaling_policy" "target_tracking" {
  name               = var.policy_name
  policy_type        = "TargetTrackingScaling"
  resource_id        = local.resource_id
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  target_tracking_scaling_policy_configuration {
    target_value       = var.target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
    disable_scale_in   = var.disable_scale_in

    customized_metric_specification {
      namespace   = var.metric_namespace
      metric_name = var.metric_name
      statistic   = "Average"
      unit        = "Count"

      # IMPORTANT: dimensions must match the published time series exactly
      dimensions {
        name  = "TestId"
        value = var.metric_test_id
      }
      dimensions {
        name  = "Cluster"
        value = var.ecs_cluster
      }
      dimensions {
        name  = "Service"
        value = var.ecs_service
      }
    }
  }
}



locals {
  resource_id = "service/${var.ecs_cluster}/${var.ecs_service}"
}

resource "aws_appautoscaling_target" "ecs_desired_count" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = local.resource_id
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "target_tracking" {
  name               = var.policy_name
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_desired_count.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_desired_count.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_desired_count.service_namespace

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
      dimensions = {
        TestId  = var.metric_test_id
        Cluster = var.ecs_cluster
        Service = var.ecs_service
      }
    }
  }
}



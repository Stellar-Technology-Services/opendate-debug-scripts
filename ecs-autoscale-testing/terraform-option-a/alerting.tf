# =============================================================================
# ECS Autoscaling Notifications via EventBridge + SNS
# =============================================================================

# SNS Topic for scaling notifications
resource "aws_sns_topic" "scaling_notifications" {
  name = "ecs-scaling-notifications"

  tags = {
    Purpose = "ECS autoscaling event notifications"
    ManagedBy = "terraform"
  }
}

# Email subscription
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.scaling_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =============================================================================
# EventBridge Rule: Capture ECS Service Actions (scale in/out events)
# =============================================================================
resource "aws_cloudwatch_event_rule" "ecs_service_action" {
  name        = "ecs-scaling-events"
  description = "Captures ECS service scaling events for ${var.ecs_cluster}/${var.ecs_service}"

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Service Action"]
    resources   = [
      {
        prefix = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${var.ecs_cluster}/${var.ecs_service}"
      }
    ]
  })

  tags = {
    Purpose   = "ECS autoscaling notifications"
    ManagedBy = "terraform"
  }
}

# EventBridge Target: Send to SNS
resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.ecs_service_action.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.scaling_notifications.arn

  # Format the message for readability
  input_transformer {
    input_paths = {
      cluster   = "$.detail.clusterArn"
      service   = "$.detail.serviceName"
      eventType = "$.detail.eventType"
      eventName = "$.detail.eventName"
      createdAt = "$.detail.createdAt"
    }
    input_template = "\"ECS Scaling Event\\n\\nCluster: <cluster>\\nService: <service>\\nEvent Type: <eventType>\\nEvent Name: <eventName>\\nTime: <createdAt>\\n\\nThis notification was triggered by an ECS service scaling action.\""
  }
}

# Allow EventBridge to publish to SNS
resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.scaling_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.scaling_notifications.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.ecs_service_action.arn
          }
        }
      }
    ]
  })
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

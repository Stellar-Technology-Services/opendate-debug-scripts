variable "aws_region" {
  description = "AWS region to create the scaling policy in."
  type        = string
  default     = "us-east-1"
}

variable "ecs_cluster" {
  description = "ECS cluster name (defaulting to stage)."
  type        = string
  default     = "opendate-stage"
}

variable "ecs_service" {
  description = "ECS service name whose desired count will be scaled."
  type        = string
  default     = "opendate-sidekiq"
}

variable "min_capacity" {
  description = "Minimum desired task count during the test."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum desired task count during the test."
  type        = number
  default     = 4
}

variable "policy_name" {
  description = "Scaling policy name."
  type        = string
  default     = "tt-syntheticload-temporary"
}

variable "metric_namespace" {
  description = "CloudWatch metric namespace for the synthetic test metric."
  type        = string
  default     = "Test/Autoscaling"
}

variable "metric_name" {
  description = "CloudWatch metric name for the synthetic test metric."
  type        = string
  default     = "SyntheticLoad"
}

variable "metric_test_id" {
  description = "Dimension value for TestId; must match what you publish in publish-metric-loop.sh."
  type        = string
  default     = "tt-synth-1"
}

variable "target_value" {
  description = "Target value for target tracking (the policy will try to keep the metric around this value)."
  type        = number
  default     = 100
}

variable "scale_out_cooldown" {
  description = "Scale-out cooldown in seconds."
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Scale-in cooldown in seconds."
  type        = number
  default     = 60
}

variable "disable_scale_in" {
  description = "If true, the policy will not scale in."
  type        = bool
  default     = false
}



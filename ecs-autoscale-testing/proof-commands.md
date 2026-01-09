## Proof package: commands to capture evidence

These commands are meant to produce copy/paste output (or screenshots) proving:

- The synthetic metric moved above/below the target
- Application Auto Scaling triggered scale-out/scale-in
- ECS service `desiredCount` changed accordingly
- Target tracking alarms were created automatically

## 0) Set variables (same as the other files)

```bash
export AWS_REGION="${AWS_REGION:-us-east-1}"          # <-- change if needed
export ECS_CLUSTER="${ECS_CLUSTER:-opendate-stage}" # stage cluster (override explicitly if needed)
export ECS_SERVICE="${ECS_SERVICE:-opendate-sidekiq}"

export RESOURCE_ID="service/${ECS_CLUSTER}/${ECS_SERVICE}"

export METRIC_NAMESPACE="${METRIC_NAMESPACE:-Test/Autoscaling}"
export METRIC_NAME="${METRIC_NAME:-SyntheticLoad}"
export METRIC_DIM_TEST_ID="${METRIC_DIM_TEST_ID:-tt-synth-1}"

export POLICY_NAME="${POLICY_NAME:-tt-syntheticload-temporary}"
```

## 1) Verify the metric data points exist (CloudWatch)

List the metric (confirms namespace/name/dimensions):

```bash
aws cloudwatch list-metrics \
  --region "$AWS_REGION" \
  --namespace "$METRIC_NAMESPACE" \
  --metric-name "$METRIC_NAME" \
  --output json
```

Pull last ~40 minutes of datapoints (covers the 10+15 min loop and some slack):

```bash
END="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
START="$(date -u -d "40 minutes ago" +"%Y-%m-%dT%H:%M:%SZ")"

aws cloudwatch get-metric-statistics \
  --region "$AWS_REGION" \
  --namespace "$METRIC_NAMESPACE" \
  --metric-name "$METRIC_NAME" \
  --dimensions Name=TestId,Value="$METRIC_DIM_TEST_ID" Name=Cluster,Value="$ECS_CLUSTER" Name=Service,Value="$ECS_SERVICE" \
  --start-time "$START" \
  --end-time "$END" \
  --period 60 \
  --statistics Average Maximum \
  --output json
```

## 2) Show scaling policy details (Application Auto Scaling)

```bash
aws application-autoscaling describe-scaling-policies \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --resource-id "$RESOURCE_ID" \
  --query "ScalingPolicies[?PolicyName=='${POLICY_NAME}']" \
  --output json
```

## 3) Scaling activities (strongest “proof” output)

This is usually the best artifact: it includes a reason message referencing the policy/metric and the capacity change.

```bash
aws application-autoscaling describe-scaling-activities \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --resource-id "$RESOURCE_ID" \
  --max-results 50 \
  --output json
```

Optional: show a compact table of recent activities:

```bash
aws application-autoscaling describe-scaling-activities \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --resource-id "$RESOURCE_ID" \
  --max-results 25 \
  --query "ScalingActivities[].{StartTime:StartTime,Status:StatusCode,Desc:Description,Cause:Cause}" \
  --output table
```

## 4) ECS desired/running counts + service events

Desired/running/pending snapshot:

```bash
aws ecs describe-services \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --services "$ECS_SERVICE" \
  --query "services[0].{serviceName:serviceName,desired:desiredCount,running:runningCount,pending:pendingCount,status:status}" \
  --output table
```

Recent ECS service events (includes “desired count changed” and task start/stop messages):

```bash
aws ecs describe-services \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --services "$ECS_SERVICE" \
  --query "services[0].events[0:20].[createdAt,message]" \
  --output table
```

If you want to watch changes live during the publish loop:

```bash
watch -n 10 "aws ecs describe-services --region \"$AWS_REGION\" --cluster \"$ECS_CLUSTER\" --services \"$ECS_SERVICE\" --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount,updated:events[0].createdAt,lastEvent:events[0].message}' --output table"
```

## 5) Confirm target tracking alarms were created

Target tracking policies create CloudWatch alarms automatically.

```bash
aws cloudwatch describe-alarms \
  --region "$AWS_REGION" \
  --alarm-name-prefix "TargetTracking-service/${ECS_CLUSTER}/${ECS_SERVICE}" \
  --query "MetricAlarms[].{Name:AlarmName,State:StateValue,Updated:StateUpdatedTimestamp}" \
  --output table
```

## 6) Cleanup (delete the temporary scaling policy)

```bash
aws application-autoscaling delete-scaling-policy \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id "$RESOURCE_ID" \
  --policy-name "$POLICY_NAME"
```

Note: the auto-created CloudWatch alarms are usually cleaned up automatically after the policy deletion, but they can linger briefly.



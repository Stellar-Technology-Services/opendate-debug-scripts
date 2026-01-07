## Goal

Create a **temporary** ECS Service auto scaling policy (Option A: **Target Tracking** using a **custom CloudWatch metric**) and a synthetic metric you can fully control, so you can prove end-to-end behavior:

CloudWatch metric → Application Auto Scaling policy → ECS `desiredCount` changes

## Prereqs

- `aws` CLI authenticated to the right account
- Permissions for:
  - `application-autoscaling:*`
  - `cloudwatch:*`
  - `ecs:DescribeServices`
- ECS service must exist (this does **not** create the service)

## Configuration (copy/paste)

Set these in your shell before running the commands below.

```bash
# --- REQUIRED / EDIT ME ---
export AWS_REGION="${AWS_REGION:-us-east-1}"          # <-- change if needed
export ECS_CLUSTER="${ECS_CLUSTER:-opendate-stage}" # stage=opendate-stage , prod=Opendate-VPC-cluster
export ECS_SERVICE="${ECS_SERVICE:-opendate-sidekiq}"

# Safe test bounds (you provided 2 / 4)
export MIN_CAPACITY="${MIN_CAPACITY:-2}"
export MAX_CAPACITY="${MAX_CAPACITY:-4}"

# Synthetic metric for the test (safe; does not touch prod metrics)
export METRIC_NAMESPACE="${METRIC_NAMESPACE:-Test/Autoscaling}"
export METRIC_NAME="${METRIC_NAME:-SyntheticLoad}"

# This MUST match the dimensions you publish in publish-metric-loop.sh
export METRIC_DIM_TEST_ID="${METRIC_DIM_TEST_ID:-tt-synth-1}"

# Target tracking behavior
export TARGET_VALUE="${TARGET_VALUE:-100}"
export SCALE_OUT_COOLDOWN="${SCALE_OUT_COOLDOWN:-60}"
export SCALE_IN_COOLDOWN="${SCALE_IN_COOLDOWN:-60}"

# Names
export POLICY_NAME="${POLICY_NAME:-tt-syntheticload-temporary}"
export RESOURCE_ID="service/${ECS_CLUSTER}/${ECS_SERVICE}"
```

## 1) Register the scalable target (DesiredCount)

This tells Application Auto Scaling it is allowed to change your ECS service desired count, and enforces min/max.

```bash
aws application-autoscaling register-scalable-target \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id "$RESOURCE_ID" \
  --min-capacity "$MIN_CAPACITY" \
  --max-capacity "$MAX_CAPACITY"
```

Verify:

```bash
aws application-autoscaling describe-scalable-targets \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --resource-id "$RESOURCE_ID" \
  --output table
```

## 2) Create the Target Tracking policy on the synthetic metric

Important: target tracking requires a **single time series**. This policy targets the metric series defined by the exact dimension set:

- `TestId=$METRIC_DIM_TEST_ID`
- `Cluster=$ECS_CLUSTER`
- `Service=$ECS_SERVICE`

```bash
aws application-autoscaling put-scaling-policy \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id "$RESOURCE_ID" \
  --policy-name "$POLICY_NAME" \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration "{
    \"TargetValue\": ${TARGET_VALUE},
    \"CustomizedMetricSpecification\": {
      \"Namespace\": \"${METRIC_NAMESPACE}\",
      \"MetricName\": \"${METRIC_NAME}\",
      \"Dimensions\": [
        {\"Name\": \"TestId\", \"Value\": \"${METRIC_DIM_TEST_ID}\"},
        {\"Name\": \"Cluster\", \"Value\": \"${ECS_CLUSTER}\"},
        {\"Name\": \"Service\", \"Value\": \"${ECS_SERVICE}\"}
      ],
      \"Statistic\": \"Average\",
      \"Unit\": \"Count\"
    },
    \"ScaleOutCooldown\": ${SCALE_OUT_COOLDOWN},
    \"ScaleInCooldown\": ${SCALE_IN_COOLDOWN},
    \"DisableScaleIn\": false
  }"
```

Capture the policy ARN (useful for cleanup):

```bash
aws application-autoscaling describe-scaling-policies \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --resource-id "$RESOURCE_ID" \
  --query "ScalingPolicies[?PolicyName=='${POLICY_NAME}'].[PolicyName,PolicyARN]" \
  --output table
```

## 3) Drive the metric (scale out then scale in)

Run:

```bash
chmod +x ./ecs-autoscale-testing/publish-metric-loop.sh
./ecs-autoscale-testing/publish-metric-loop.sh
```

## 4) Watch desired count change

In another terminal:

```bash
watch -n 10 "aws ecs describe-services --region \"$AWS_REGION\" --cluster \"$ECS_CLUSTER\" --services \"$ECS_SERVICE\" --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount,deployments:deployments[*].{status:status,desired:desiredCount,running:runningCount}}' --output table"
```

## 5) Cleanup (remove temporary policy)

```bash
POLICY_ARN="$(aws application-autoscaling describe-scaling-policies \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --resource-id "$RESOURCE_ID" \
  --query "ScalingPolicies[?PolicyName=='${POLICY_NAME}'].PolicyARN | [0]" \
  --output text)"

echo "Deleting policy: $POLICY_ARN"

aws application-autoscaling delete-scaling-policy \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id "$RESOURCE_ID" \
  --policy-name "$POLICY_NAME"
```

Optional: restore original min/max if you changed them for the test (run `register-scalable-target` again with your normal bounds).



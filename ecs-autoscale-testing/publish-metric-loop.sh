#!/usr/bin/env bash
set -euo pipefail

# Publishes a synthetic CloudWatch metric for a single time series:
# - HIGH for 10 minutes (1/min)
# - LOW  for 15 minutes (1/min)
#
# This is meant to drive an ECS Target Tracking policy configured with:
# Namespace=Test/Autoscaling, MetricName=SyntheticLoad, and matching Dimensions.

AWS_REGION="${AWS_REGION:-us-east-1}"
METRIC_NAMESPACE="${METRIC_NAMESPACE:-Test/Autoscaling}"
METRIC_NAME="${METRIC_NAME:-SyntheticLoad}"

ECS_CLUSTER="${ECS_CLUSTER:-opendate-stage}" # stage cluster (override explicitly if needed)
ECS_SERVICE="${ECS_SERVICE:-opendate-sidekiq}"

# Must match the scaling policy's dimension set exactly
METRIC_DIM_TEST_ID="${METRIC_DIM_TEST_ID:-tt-synth-1}"

# Target tracking target value (for reference)
TARGET_VALUE="${TARGET_VALUE:-100}"

# Publish cadence
PERIOD_SECONDS="${PERIOD_SECONDS:-60}"

# Drive above/below target
HIGH_VALUE="${HIGH_VALUE:-200}"   # > TARGET_VALUE to encourage scale-out
LOW_VALUE="${LOW_VALUE:-0}"       # < TARGET_VALUE to encourage scale-in

# Durations
# HIGH: 4 min is enough (scale-out alarm needs 3 datapoints)
# LOW: 16 min required (scale-in alarm needs 15 consecutive datapoints)
HIGH_MINUTES="${HIGH_MINUTES:-4}"
LOW_MINUTES="${LOW_MINUTES:-16}"

metric_data() {
  local value="$1"
  # Use a stable, single time series (dimension set must match the policy)
  printf 'MetricName=%s,Dimensions=[{Name=TestId,Value=%s},{Name=Cluster,Value=%s},{Name=Service,Value=%s}],Unit=Count,Value=%s' \
    "$METRIC_NAME" \
    "$METRIC_DIM_TEST_ID" \
    "$ECS_CLUSTER" \
    "$ECS_SERVICE" \
    "$value"
}

publish_once() {
  local value="$1"
  aws cloudwatch put-metric-data \
    --region "$AWS_REGION" \
    --namespace "$METRIC_NAMESPACE" \
    --metric-data "$(metric_data "$value")" >/dev/null

  # UTC timestamp for easy correlation with scaling activities
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") published ${METRIC_NAMESPACE}/${METRIC_NAME}=${value} (TestId=${METRIC_DIM_TEST_ID}, Cluster=${ECS_CLUSTER}, Service=${ECS_SERVICE})"
}

echo "Region:           $AWS_REGION"
echo "Metric:           ${METRIC_NAMESPACE}/${METRIC_NAME}"
echo "Dimensions:       TestId=${METRIC_DIM_TEST_ID}, Cluster=${ECS_CLUSTER}, Service=${ECS_SERVICE}"
echo "TargetValue:      $TARGET_VALUE (reference)"
echo "High phase:       ${HIGH_MINUTES} min @ ${HIGH_VALUE} (every ${PERIOD_SECONDS}s)"
echo "Low phase:        ${LOW_MINUTES} min @ ${LOW_VALUE} (every ${PERIOD_SECONDS}s)"
echo

echo "== HIGH phase (expect scale-out) =="
for ((i=1; i<=HIGH_MINUTES; i++)); do
  publish_once "$HIGH_VALUE"
  if [[ "$i" -lt "$HIGH_MINUTES" ]]; then
    sleep "$PERIOD_SECONDS"
  fi
done

echo
echo "== LOW phase (expect scale-in) =="
for ((i=1; i<=LOW_MINUTES; i++)); do
  publish_once "$LOW_VALUE"
  if [[ "$i" -lt "$LOW_MINUTES" ]]; then
    sleep "$PERIOD_SECONDS"
  fi
done

echo
echo "Done publishing. Now pull proof artifacts with:"
echo "  ./ecs-autoscale-testing/proof-commands.md"



with ecs, where are autoscaling settings configured at?

In Amazon ECS, autoscaling is not configured inside the ECS service definition itself. It is configured in Application Auto Scaling, with CloudWatch alarms providing the signals. Where you configure it depends on what you are scaling.

1. ECS Service Auto Scaling (most common)

What it scales

The desired task count of an ECS service

Where it is configured

Application Auto Scaling

Target: ecs:service:DesiredCount

CloudWatch Alarms

Trigger scale-in / scale-out actions

How you typically set it up

Via:

AWS Console → ECS → Service → Auto Scaling (this is just a UI over Application Auto Scaling)

CloudFormation / Terraform

AWS CLI (application-autoscaling)

Key point

ECS “service autoscaling” is actually Application Auto Scaling managing the ECS service.

ECS itself does not own the scaling logic.

2. ECS Capacity Auto Scaling (cluster-side)

This answers a different question: do I have enough compute to run more tasks?

EC2-backed ECS

What it scales

EC2 instances in an Auto Scaling Group

Where it is configured

EC2 Auto Scaling Group

Scaling policies

CloudWatch alarms

Notes

ECS just places tasks; it does not add instances.

Capacity Providers often manage this linkage automatically.

Fargate-backed ECS

What it scales

Nothing you configure directly

AWS manages the underlying capacity

Where it is configured

Nowhere (from your perspective)

You only scale task count

3. ECS Capacity Providers (recommended pattern)

Capacity Providers connect:

Service task scaling ↔ cluster capacity scaling

Where settings live

Capacity Provider

Managed scaling parameters

Application Auto Scaling

For task count

EC2 Auto Scaling Group

For instance count (EC2 only)

This avoids “task wants to scale but no capacity exists” problems.

4. Quick mental model
Concern	Configured In
Scale number of running tasks	Application Auto Scaling
Scale EC2 instances	EC2 Auto Scaling Group
Connect service ↔ capacity	ECS Capacity Provider
Metrics & triggers	CloudWatch
5. Common confusion points

ECS Service Auto Scaling ≠ EC2 Auto Scaling

Console paths can be misleading: ECS console edits Application Auto Scaling under the hood

Terraform/CloudFormation often define scaling outside the ECS service resource

If you want, tell me:

EC2 or Fargate?

Console vs IaC (Terraform / CloudFormation)?

Metric-based or schedule-based scaling?

I can point you to the exact resource blocks or console screens to inspect.

how can i configure ecs to use a queue depth of a sidekiq queue (stored in redis or postgres, I'm not sure) instead of something like cpu or memory?
Thought for 6s

You can, but the key constraint is this:

ECS service auto scaling (Application Auto Scaling) can only scale on CloudWatch metrics—so if you want “Sidekiq queue depth” to drive scaling, you must publish queue depth (or latency) into CloudWatch as either a custom metric or an EMF-extracted metric, and then attach an ECS scaling policy to that metric. 
AWS Documentation
+2
AWS Documentation
+2

Below is a practical pattern that works well in production.

1. Decide what you’ll scale on: queue size or queue latency

For Sidekiq, you can measure at least:

Queue size (count of jobs) (e.g., Sidekiq::Queue.new("default").size) 
RubyDoc

Queue latency (age of oldest job) (e.g., Sidekiq::Queue.new("default").latency) 
RubyDoc

In practice, latency is often a better SLO-aligned scaling signal than raw depth (depth can grow but still be “okay” if workers are fast).

Also, Sidekiq queues “live in Redis” in the standard Sidekiq architecture. 
judoscale.com
+1

(If your team is unsure whether Redis is in play, that’s the first thing I’d confirm in your app config; Sidekiq’s baseline design uses Redis.)

2. Publish the metric into CloudWatch

You have two common approaches:

Option A (simple): Scheduled poller publishes via PutMetricData

Run a small poller on a schedule that:

queries Redis / Sidekiq API for depth/latency

calls CloudWatch PutMetricData with a custom metric (namespace like MyApp/Sidekiq) 
AWS Documentation

Where to run the poller:

Lambda + EventBridge schedule (common and cheap)

A tiny “metrics” ECS task run on a schedule (EventBridge → RunTask)

A sidecar container (less common if you want one metric for the whole service)

Option B (clean in container environments): EMF logs → CloudWatch metric extraction

Instead of calling PutMetricData, your poller writes metrics in Embedded Metric Format (EMF) to CloudWatch Logs; CloudWatch extracts them into metrics automatically. 
AWS Documentation
+2
AWS Documentation
+2

This is attractive in ECS because it avoids direct metric API calls from every task, but you need to implement EMF correctly.

3. Configure ECS Service Auto Scaling to use that metric

Once the metric exists in CloudWatch, configure Application Auto Scaling for your ECS service:

Scalable target: ecs:service:DesiredCount

Policy type: Target tracking (recommended) or Step scaling

Metric: your custom CloudWatch metric (queue depth / latency)

Target tracking will automatically create and manage the CloudWatch alarms for scaling. 
AWS Documentation
+1

AWS also documents that ECS service scaling can use “these and other CloudWatch metrics,” i.e., custom metrics. 
AWS Documentation

4. Pick a sane target: “backlog per task” (not raw backlog)

A common mistake is scaling directly on queue depth without accounting for task count. Prefer a target like:

jobs_per_task = queue_depth / running_tasks

or latency_seconds directly

Application Auto Scaling supports metric math so you can compute ratios and scale on the derived value. 
AWS Documentation

This makes scaling behavior far more stable as the service grows.

5. Operational cautions (to avoid “thrash”)

Publish metrics at a consistent interval (e.g., every 30–60 seconds) so scaling has steady input. (This is a common best practice implied by AWS guidance around publishing custom metrics for scaling.) 
AWS Documentation

Set cooldowns / stabilization windows so one spike doesn’t oscillate task count.

Ensure your ECS cluster capacity can actually expand (EC2 ASG capacity provider) or you’re on Fargate.

If multiple Sidekiq queues exist, decide whether to scale on:

the “critical” queue only

max(queue_depth)

weighted sum of depths

Minimal “how-to” summary

Poll Sidekiq queue depth/latency (Redis-backed) 
judoscale.com
+1

Push to CloudWatch (PutMetricData or EMF) 
AWS Documentation
+1

Create an ECS scaling policy using that metric (target tracking / step scaling) 
AWS Documentation
+1

If you tell me whether you’re on Fargate vs EC2, and whether you prefer Terraform or Console/CLI, I’ll give you a concrete implementation (poller + metric schema + the exact scaling policy configuration), including a recommended target value based on Sidekiq concurrency (threads per process × processes per task).

show me a simple cli example of querying sidekiq and then publishing the metric to cloudwatch (prefer all via cli to make it easier for me to understand)

Below is a minimal, CLI-only example that:

queries Sidekiq queue depth directly from Redis using redis-cli

publishes that value as a custom CloudWatch metric using the AWS CLI

This is the simplest mental model: queue depth = Redis list length.

Prereqs

redis-cli installed

AWS CLI configured (credentials + region)

Your Sidekiq uses Redis (standard Sidekiq architecture)

Sidekiq stores queue contents in Redis lists named:

queue:<queue_name>
Example: queue:default

1) Query Sidekiq queue depth (Redis LLEN)
Example: get depth of the default queue
REDIS_HOST="my-redis.example.cache.amazonaws.com"
REDIS_PORT="6379"
QUEUE="default"

QUEUE_DEPTH=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LLEN "queue:${QUEUE}")

echo "Queue ${QUEUE} depth: ${QUEUE_DEPTH}"


What it’s doing: LLEN queue:default returns the number of jobs currently in that queue.

If Redis requires auth:

REDIS_PASSWORD="yourpassword"
QUEUE_DEPTH=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" LLEN "queue:${QUEUE}")

2) Publish that metric to CloudWatch (PutMetricData)
Publish the queue depth as a custom metric
AWS_REGION="us-east-1"
NAMESPACE="MyApp/Sidekiq"
METRIC_NAME="QueueDepth"
SERVICE_NAME="sidekiq-workers"   # optional dimension
CLUSTER_NAME="my-ecs-cluster"    # optional dimension

aws cloudwatch put-metric-data \
  --region "$AWS_REGION" \
  --namespace "$NAMESPACE" \
  --metric-data "MetricName=${METRIC_NAME},Dimensions=[{Name=Queue,Value=${QUEUE}},{Name=Service,Value=${SERVICE_NAME}},{Name=Cluster,Value=${CLUSTER_NAME}}],Unit=Count,Value=${QUEUE_DEPTH}"

3) Full end-to-end script (copy/paste runnable)
#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIG ----
REDIS_HOST="my-redis.example.cache.amazonaws.com"
REDIS_PORT="6379"
QUEUE="default"
# REDIS_PASSWORD=""   # uncomment and set if needed

AWS_REGION="us-east-1"
NAMESPACE="MyApp/Sidekiq"
METRIC_NAME="QueueDepth"
SERVICE_NAME="sidekiq-workers"
CLUSTER_NAME="my-ecs-cluster"
# ----------------

# Query Redis for Sidekiq queue depth
# If using password auth, add: -a "$REDIS_PASSWORD"
QUEUE_DEPTH=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LLEN "queue:${QUEUE}")

echo "Sidekiq queue '${QUEUE}' depth: ${QUEUE_DEPTH}"

# Publish custom metric to CloudWatch
aws cloudwatch put-metric-data \
  --region "$AWS_REGION" \
  --namespace "$NAMESPACE" \
  --metric-data "MetricName=${METRIC_NAME},Dimensions=[{Name=Queue,Value=${QUEUE}},{Name=Service,Value=${SERVICE_NAME}},{Name=Cluster,Value=${CLUSTER_NAME}}],Unit=Count,Value=${QUEUE_DEPTH}"

echo "Published CloudWatch metric: ${NAMESPACE}/${METRIC_NAME}=${QUEUE_DEPTH}"


Run it:

chmod +x publish-sidekiq-queue-depth.sh
./publish-sidekiq-queue-depth.sh

4) Validate the metric exists (CLI)

Metrics show up quickly, but sometimes it takes a couple of minutes.

List the metric
aws cloudwatch list-metrics \
  --region us-east-1 \
  --namespace "MyApp/Sidekiq" \
  --metric-name "QueueDepth"

Query recent data
END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START=$(date -u -d "10 minutes ago" +"%Y-%m-%dT%H:%M:%SZ")

aws cloudwatch get-metric-statistics \
  --region us-east-1 \
  --namespace "MyApp/Sidekiq" \
  --metric-name "QueueDepth" \
  --dimensions Name=Queue,Value=default \
  --start-time "$START" \
  --end-time "$END" \
  --period 60 \
  --statistics Average Maximum

Notes that will matter later (but don’t complicate the first step)

This only publishes queue depth, not latency. (Depth is simplest because it’s a single Redis command.)

For autoscaling, you’ll typically:

publish every 30–60 seconds

scale on queue depth per task using CloudWatch metric math (more stable)

If you want the next step, I can provide an equally simple CLI example of creating the ECS service scaling policy that scales DesiredCount based on MyApp/Sidekiq QueueDepth (target tracking or step scaling).

it turns out we already have queuesize published to cloudwatch.  why do these not show up as metrics i can autoscale with in the ECS configuration?

What you’re running into is a console/UI limitation, not an AWS limitation.

Why your QueueSize metric doesn’t appear in the ECS “target tracking” dropdown

In the ECS Service → Auto Scaling → Target tracking policy editor, the “Metric type” dropdown is intentionally limited to only a small set of predefined / supported target-tracking templates:

ECSServiceAverageCPUUtilization

ECSServiceAverageMemoryUtilization

ALBRequestCountPerTarget

That UI does not expose “custom metrics” (like your Sidekiq QueueSize) even if they’re in CloudWatch and graphable (as your screenshot shows).

So:

✅ Your metric exists and is valid

❌ The ECS console target-tracking picker won’t show it, because it only supports those built-in metric types

This is why you can browse it under CloudWatch metrics, but can’t pick it from that ECS scaling dialog.

What you need to do instead

You have two clean options:

Option A (recommended): Create the scaling policy in Application Auto Scaling using a “customized metric specification”

ECS service scaling is actually managed by Application Auto Scaling under the hood. The ECS console just gives a simplified UI.

If you create the scaling policy via:

Application Auto Scaling console

AWS CLI

Terraform / CloudFormation

…you can target track on any CloudWatch metric, including QueueSize.

Concretely, you create a target tracking policy with:

ServiceNamespace = ecs

ScalableDimension = ecs:service:DesiredCount

CustomizedMetricSpecification pointing at your QueueSize metric namespace and dimensions

Option B: Use Step Scaling from CloudWatch Alarms

This is also valid:

Create a CloudWatch Alarm on QueueSize

Attach that alarm to a Step Scaling policy for the ECS service

Step scaling is sometimes preferable if you want very explicit “if queue > X then add N tasks”.

The most common “gotcha” even after you do it right

Even when you use Application Auto Scaling directly, your metric must be defined with the exact same dimensions you specify in the scaling policy.

From your screenshot, it looks like:

Metric name: QueueSize

Dimension: QueueName=<queue>

So your scaling policy must specify that same dimension set (or use metric math / a rollup metric).

Also: target tracking needs a single time series.

If you have 9 queues, you either:

scale on one queue (QueueName=default), or

publish an aggregate metric (TotalQueueSize), or

use metric math (max/sum) in step scaling, because target tracking has limitations around math expressions depending on how you configure it.

Why the ECS console works this way (so you know it’s not you)

The ECS console is designed to keep the “easy path” simple and safe:

CPU/memory are always available for services

ALB request count is common for web services

Custom metrics require you to know namespace/dimensions/statistics precisely, so AWS pushes you to Application Auto Scaling / IaC for that

What I recommend for your Sidekiq case

Pick QueueName=default (or whatever drives the main backlog)

Create a target tracking policy in Application Auto Scaling using your metric

Optionally: publish a single rollup metric like SidekiqTotalQueueSize to avoid per-queue complexity

If you want, I can give you the exact CLI commands

If you paste:

CloudWatch namespace for the metric (it’ll be on the metric detail page)

One sample dimension set (you have QueueName, but confirm exact spelling/case)

ECS clusterName and serviceName

…I’ll give you a working CLI sequence:

register-scalable-target

put-scaling-policy using CustomizedMetricSpecification referencing your QueueSize

That will make scaling work immediately even though the ECS UI never shows the metric in the dropdown.

show me cli for Option A

Below is a complete AWS CLI example for Option A: ECS Service Target Tracking scaling using your existing CloudWatch custom metric QueueSize (dimension QueueName=<queue>).

This does two things:

Register your ECS service as a scalable target (DesiredCount)

Create a target tracking scaling policy on your custom metric

0) Set variables (edit these)
AWS_REGION="us-east-1"

CLUSTER_NAME="my-ecs-cluster"
SERVICE_NAME="my-sidekiq-service"

MIN_CAPACITY="1"
MAX_CAPACITY="20"

# CloudWatch metric details:
METRIC_NAMESPACE="YourMetricNamespaceHere"   # e.g. "Sidekiq" or "MyApp/Sidekiq"
METRIC_NAME="QueueSize"
QUEUE_NAME="default"                          # the queue you want to scale on


Important: The metric dimension key must match exactly what you see in CloudWatch.
In your screenshot it looks like QueueName, not Queue.

1) Register the scalable target
aws application-autoscaling register-scalable-target \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
  --min-capacity "$MIN_CAPACITY" \
  --max-capacity "$MAX_CAPACITY"

2) Create a target tracking scaling policy on QueueSize

This example tries to keep queue depth around 100 jobs (tune this).

TARGET_QUEUE_SIZE="100"
SCALE_OUT_COOLDOWN="60"
SCALE_IN_COOLDOWN="180"

aws application-autoscaling put-scaling-policy \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
  --policy-name "sidekiq-queue-size-tt" \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration "{
    \"TargetValue\": ${TARGET_QUEUE_SIZE},
    \"CustomizedMetricSpecification\": {
      \"Namespace\": \"${METRIC_NAMESPACE}\",
      \"MetricName\": \"${METRIC_NAME}\",
      \"Dimensions\": [
        {\"Name\": \"QueueName\", \"Value\": \"${QUEUE_NAME}\"}
      ],
      \"Statistic\": \"Average\",
      \"Unit\": \"Count\"
    },
    \"ScaleOutCooldown\": ${SCALE_OUT_COOLDOWN},
    \"ScaleInCooldown\": ${SCALE_IN_COOLDOWN},
    \"DisableScaleIn\": false
  }"


What this does

If QueueSize is above 100, it scales out

If QueueSize is below 100, it scales in

Cooldowns prevent thrashing

3) Verify the scaling policy was created
aws application-autoscaling describe-scaling-policies \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}"


You should see sidekiq-queue-size-tt.

4) Verify the ECS service has scaling registered
aws application-autoscaling describe-scalable-targets \
  --region "$AWS_REGION" \
  --service-namespace ecs \
  --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}"

5) Confirm CloudWatch alarms were created (target tracking auto-creates these)

Target tracking policies automatically create CloudWatch alarms.

aws cloudwatch describe-alarms \
  --region "$AWS_REGION" \
  --alarm-name-prefix "TargetTracking-service/${CLUSTER_NAME}/${SERVICE_NAME}"


If you don’t see them immediately, give it a minute; they are created asynchronously.

Notes you should know (so you don’t get surprised)
A) Metric namespace and dimensions must match exactly

If your metric is under something like QueueName (as shown), use that exact spelling.
If you get validation errors, double-check the metric in CloudWatch → Graphed metrics → JSON.

B) TargetTrackingScaling expects a single time series

So you can’t directly scale on “all queues” unless:

you publish an aggregate metric (best), or

you pick one queue that represents your overall backlog, or

you do step scaling with alarms + metric math (can do max/sum across queues)

C) Statistic choice

Average works for a single dimensioned metric stream.

Some people prefer Maximum for queue depth so spikes scale faster.
If you choose Maximum, change "Statistic": "Maximum".

Quick “find my namespace + dimensions” CLI helper

If you’re not sure what namespace the metric is in:

aws cloudwatch list-metrics \
  --region "$AWS_REGION" \
  --metric-name "QueueSize"


This will return the namespace and the dimension names/values it sees.

If you paste the output of list-metrics for QueueSize (namespace + dimension key names), I can rewrite the policy JSON to exactly match what you have so it works on the first run.

there is some step-scaling built int to the ECS UI here.  The customer already has an alarm configured for queue size > 1000, but nothing that would match a step-down (yet).  is this a viable path?  Maybe after setting up some specialized alarms etc.?

Yes — this is a viable path, and it’s a common way to scale ECS services on custom CloudWatch metrics when the “target tracking” UI won’t let you select them. What you’re seeing in the ECS UI is effectively a guided setup for Application Auto Scaling step scaling policies driven by CloudWatch alarms.

That said, you should treat it as viable only if you design the alarms and step policy carefully, otherwise you’ll get either:

scale-out that never comes back down, or

“yo-yo scaling” (scale out then immediately scale in), or

slow responsiveness because each alarm can only fire at the granularity you choose.

Below is a clear way to think about it.

Why it works (and why it can be better than target tracking here)
Step scaling is alarm-driven

Instead of “keep metric around X” (target tracking), step scaling is:

Alarm enters ALARM → execute “add N tasks”

Alarm enters ALARM (for scale-in alarm) → execute “remove N tasks”

This is a good fit when you already have:

a metric like SidekiqSumAllQueues

and an existing alarm like “Queue > 1000”

It also gives you explicit control over scaling behavior and avoids some target tracking limitations with custom metrics and/or metric math.

Your current setup is incomplete (and the UI screenshot shows a pitfall)

From your screenshot, it looks like you selected the same alarm for both add and remove policies (“SideKiqAllQueueSize”), with a condition:

SidekiqSumAllQueues > 1000

That cannot work for scale-in.

Why:

Scale-in needs an alarm that triggers when the metric is low, e.g.:

QueueSize < 200 for 10 minutes, etc.

Otherwise your scale-in policy would never trigger (or worse, would trigger incorrectly if misconfigured).

So the path is viable, but you must create at least one additional “low backlog” alarm (and possibly a few “high backlog” alarms for multiple steps).

Recommended step scaling design for Sidekiq queue depth
1) Use two alarms minimum

You need:

Scale-out alarm: QueueSize > 1000

Scale-in alarm: QueueSize < 200 (or similar)

Important: follow AWS’s best practice guidance (also shown in your UI) to ensure the thresholds are meaningfully separated (the UI mentions 10% separation; in practice for queues you often want much more separation).

This creates a hysteresis band:

above 1000 → scale out

below 200 → scale in

between 200 and 1000 → do nothing

That prevents thrash.

2) Don’t scale on “0 seconds” evaluation

Your screenshot shows:

1 consecutive period(s) of 0 seconds

That is almost certainly because the alarm is configured with either:

1 datapoint, 0/invalid period, or

a metric math alarm with odd settings

For queue depth scaling you generally want:

period = 60 seconds

evaluation periods = 2–5

datapoints to alarm = 2–3

Example:

Scale-out: QueueSize > 1000 for 2 of 3 minutes

Scale-in: QueueSize < 200 for 10 of 10 minutes (more conservative)

This prevents scaling based on brief spikes and also prevents scale-in too aggressively.

3) Use multiple scale-out steps (optional but usually worth it)

Instead of a single alarm at 1000 that always adds +1, you can create alarms like:

QueueSize > 1000 → +1

QueueSize > 5000 → +3

QueueSize > 20000 → +8

You can do this either as:

separate alarms (simplest to reason about), or

one alarm with step adjustments that reference the metric value (more elegant, but more complex)

For customers, multiple alarms is usually the most understandable.

Example “viable, simple” configuration
Scale-out

Alarm: SidekiqSumAllQueues > 1000 for 2 of 3 minutes
Policy: ChangeInCapacity +1, cooldown 60 seconds

You already have most of this.

Scale-in (new)

Alarm: SidekiqSumAllQueues < 200 for 10 of 10 minutes
Policy: ChangeInCapacity -1, cooldown 300–600 seconds

This will gently ratchet down once the system has been stable.

When step scaling is not the best choice

There are a few cases where target tracking is better:

If queue depth changes constantly and you want a smooth “keep it around X”

If you want more predictable “backlog per worker” behavior

If you’d rather not manage alarms manually

But since your metric already exists and you already have an alarm, step scaling is absolutely a pragmatic and operationally safe choice—provided you add a scale-in alarm and build hysteresis.

Strong recommendation: scale on latency or on backlog per task (if you can)

Queue depth is okay, but it’s not always the best indicator of user impact.

If you can publish:

QueueLatencySeconds (age of oldest job), or

a metric math expression like QueueDepth / RunningTaskCount

…then you can scale on something closer to “are we keeping up?”
That said, the queue depth alarm-based approach is still completely viable.

What I’d do next (minimum effort path)

Keep the existing Scale-out alarm at > 1000

Create a Scale-in alarm at < 200 over a longer window

Set scale-in cooldown longer than scale-out cooldown

Test with forced backlog (enqueue jobs) and watch desired count change

Add additional scale-out alarms for higher thresholds if needed

If you want, paste:

the namespace/metric name/dimensions of SidekiqSumAllQueues

current min/max desired count

typical worker concurrency per task (Sidekiq threads)

…and I’ll recommend concrete thresholds and cooldowns that match your throughput (including how to avoid scaling down while there are still running jobs).

okay it's been a couple of days.  give me a summary of our conversation/options/recommendations

Here is a consolidated summary of what we covered, the options available, and the recommendations that follow from your situation (ECS + Sidekiq + custom queue metrics already in CloudWatch).

1) What you were trying to achieve

You want ECS auto scaling to respond to Sidekiq queue backlog, rather than CPU/memory. You also clarified that:

You are running Sidekiq workers in ECS.

You want scaling driven by queue depth (and potentially other queue signals).

You discovered that queue size is already being published to CloudWatch (multiple queues, dimensioned by QueueName).

2) Key constraints we identified
A) ECS Target Tracking UI is limited

The ECS console’s “Target tracking scaling” drop-down only allows:

ECSServiceAverageCPUUtilization

ECSServiceAverageMemoryUtilization

ALBRequestCountPerTarget

It does not list custom CloudWatch metrics, even if they exist and are graphable. This is why your Sidekiq queue metric does not appear in that UI, despite being present in CloudWatch.

B) Custom metrics are still absolutely usable

The limitation is only in the ECS UI. Under the hood, scaling is performed by Application Auto Scaling, which supports scaling on custom metrics and metric math if you configure it through:

Application Auto Scaling console

AWS CLI

Terraform / CloudFormation

3) Options we discussed
Option A (Target Tracking on custom CloudWatch metric) — recommended for “smooth” scaling

How it works

You register the ECS service as a scalable target (ecs:service:DesiredCount)

You create a TargetTrackingScaling policy using a CustomizedMetricSpecification pointing to your QueueSize metric

Pros

Generally produces stable, smooth behavior

Auto-creates CloudWatch alarms

Easier operationally than manually maintaining many alarms

Cons

Not supported in the ECS console UI for metric selection

Requires CLI/IaC

For multiple queues, you must pick:

one queue, or

publish an aggregate metric, or

scale on a derived metric (may require metric math decisions)

We provided

A working CLI sequence using:

aws application-autoscaling register-scalable-target

aws application-autoscaling put-scaling-policy with CustomizedMetricSpecification

Option B (Step Scaling using CloudWatch alarms) — very viable, especially given the customer already has an alarm

How it works

You keep or create CloudWatch alarms on queue metrics

You attach those alarms to StepScaling policies that add/remove tasks

Pros

Fully supported through the ECS console UI (and CLI/IaC)

Fits your situation because the customer already has a queue-size alarm

Very explicit behavior (e.g., “if queue > 1000, add 1”)

Cons

You must design alarms carefully to avoid thrash

Requires at least two alarms (scale-out and scale-in)

Harder to get “smooth” proportional scaling; often becomes “ladder-like” unless you add multiple steps/alarms

Important finding

The customer currently has a scale-out alarm (QueueSize > 1000), but no scale-in alarm, meaning you cannot safely implement full step scaling yet.

You also noticed that using the same “>1000” alarm for scale-in is invalid (it would never scale in).

4) Recommendations we landed on (given what you found in the environment)
Recommendation 1: Step scaling is viable and probably the fastest path if you add a scale-in alarm

Because you already have:

queue metrics published in CloudWatch

an existing queue alarm

ECS console support for step scaling

The pragmatic approach is:

Use that existing alarm for scale-out

Create a second alarm for scale-in

And then attach two step scaling policies:

Scale-out policy triggered by QueueSize > X

Scale-in policy triggered by QueueSize < Y

Recommendation 2: Add hysteresis and conservative scale-in to avoid oscillation

To prevent thrash:

Use a meaningful separation between thresholds (e.g., >1000 scale out, <200 scale in)

Make scale-in slower / more conservative:

longer evaluation period

longer cooldown

Recommendation 3: Fix alarm evaluation period issues

You showed an alarm config that effectively behaved like:

1 datapoint

~instant evaluation (in the UI it showed “0 seconds”)

For queue-based scaling, you should generally:

use a period like 60 seconds

require multiple datapoints for scale-out (e.g., 2 of 3)

require longer stability for scale-in (e.g., 10 of 10)

Recommendation 4: Consider multi-step scale-out (optional, but often necessary)

If backlogs can spike dramatically, a single “>1000 add 1” policy is usually too slow.

Instead:

>1000 → +1

>5000 → +3

>20000 → +8

This can be done with multiple alarms (simplest operationally) or a more complex step adjustment policy.

5) “Better later” scaling signals we mentioned

Queue depth works, but if you want a more SLO-aligned signal:

Queue latency (age of oldest job) tends to scale better than raw depth

Backlog per task (QueueDepth / RunningTaskCount) is more stable than raw depth

Either can be published and used in Application Auto Scaling.

6) Final guidance on what to do next

Given where you ended up (queue size already published + existing alarm), the best next step is:

Implement step scaling via ECS UI:

keep the existing scale-out alarm

add a scale-in alarm (QueueSize < Y)

Choose thresholds and cooldowns that prevent flapping:

faster scale-out

slower scale-in

If needed, add additional scale-out alarms for larger backlogs

Once stable, consider moving to Option A (target tracking via CLI/IaC) for smoother behavior or a more sophisticated metric (latency, backlog/task).

If you want, I can propose specific thresholds and cooldowns that are defensible, but I’d need two operational inputs:

typical Sidekiq throughput per task (threads × jobs/sec)

acceptable queue latency or “time to drain” target (your performance expectation)

Even without those, the two-alarm step scaling pattern above is the correct next move.

let's go back to using Option A

the problem i have is that i need to be able to test and prove that this will work.  I cannot just "do" it in prod, and the stage environment has no real traffic.  ideas for testing?

You’re thinking about this correctly: Option A (target tracking on a custom CloudWatch metric) is the cleanest, but you need a way to prove it works without risking production and without relying on “organic” staging traffic.

The good news is you can test this deterministically with controlled inputs. The key is that autoscaling is driven by two things:

CloudWatch metric values over time

The Application Auto Scaling policy reacting to those values by changing ECS DesiredCount

So your test strategy should focus on generating predictable metric conditions and verifying the service scales accordingly.

Below are several viable test approaches, ordered from “lowest risk / easiest” to “most realistic”.

Option 1 (Best for proof): Create a test scaling policy on a test metric you control
Why this works

You can prove the end-to-end flow (CloudWatch metric → scaling policy → ECS DesiredCount changes) without touching Sidekiq or Redis at all.

How

Create a separate custom metric, e.g. Test/Scaling → TestLoad

Attach Option A scaling policy to that metric for your ECS service

Use the AWS CLI to publish controlled values to CloudWatch:

publish “high” values for a few minutes → observe scale out

publish “low” values → observe scale in

Pros

Completely deterministic

No dependency on traffic or Redis

Low risk and fast

Produces screenshots/logs you can show a customer

Cons

Doesn’t prove Sidekiq metric correctness (only scaling path)

What you can prove

Customized metric target tracking works for ECS service scaling

Cooldowns / min/max behavior

Scale-in/out stability

CloudWatch alarms created by target tracking

Implementation notes

Use a distinct policy name, like tt-test-metric

Keep min/max narrow during test (e.g., min=1 max=4)

Remove the policy after test

Option 2: Publish synthetic SidekiqQueueSize values (no real backlog)

If you want to prove scaling works with the actual metric name/namespace (e.g., QueueSize), you can publish values directly.

Key caveat

You must be careful not to contaminate the same metric time series used in prod. You can avoid this by:

using a different dimension value, e.g. QueueName=test-autoscale

and pointing the scaling policy at that dimension

How

Ensure QueueSize metric exists for QueueName=test-autoscale

Create a scaling policy targeting QueueName=test-autoscale

Publish queue depth values with CLI

Pros

Proves custom metric configuration is correct (namespace/dimensions)

Still deterministic, no traffic required

Cons

Still not “real” Sidekiq backlog, but much closer

Option 3: Generate actual Sidekiq backlog in stage with a job flooder

If stage uses the same Redis/Sidekiq architecture, you can create a controlled backlog.

Approaches

Add a temporary endpoint / rake task: enqueue N jobs

A one-off script container (“load generator”) that enqueues jobs at a known rate

A “sleeper job” (each job sleeps 1–5 seconds) to guarantee backlog accumulates

How to test

Set stage service min=1 max=10

Put scaling policy on the real stage queue metric

Start flooder, watch queue grow, observe scale-out

Stop flooder, watch queue drain, observe scale-in

Pros

Most realistic and easiest to explain

Proves the metric source + scaling end-to-end

Cons

Requires stage Sidekiq to actually be configured correctly

Requires safe test jobs (must not impact real external systems)

Sometimes stage isn’t wired end-to-end enough to run jobs meaningfully

Mitigation
Use “no-op” jobs that only sleep / write to logs.

Option 4: Use a canary ECS service attached to the same cluster

If you cannot safely scale the real service even in prod, you can:

Deploy a new ECS service: sidekiq-autoscale-canary

Use the same task definition but point it at a safe queue / environment variables

Apply autoscaling policy to the canary only

Use either synthetic metrics or a controlled backlog

Pros

Proves scaling behavior without affecting primary service

You can run it in prod safely if it’s isolated

Cons

Requires infra/app work to create a canary service

What to measure / how to “prove” it

For any of these tests, your proof should be based on:

A) CloudWatch metric chart

Show the metric crossing above and below the target value.

B) ECS Service events

ECS service events will show:

desired count changed

tasks started/stopped

C) Application Auto Scaling activity history

This is the strongest evidence:

scaling activity triggered by policy

reason statement referencing metric

CLI:

aws application-autoscaling describe-scaling-activities \
  --service-namespace ecs \
  --resource-id "service/<cluster>/<service>"

D) CloudWatch alarms created by target tracking

Target tracking policies create alarms named like:
TargetTracking-service/<cluster>/<service>-AlarmHigh-...

Recommended test plan (what I’d do in your shoes)

Given your constraints (no staging traffic, can’t “just do prod”), the best path is a two-phase test:

Phase 1 — Prove the scaling mechanism works (synthetic metric test)

Create a test metric + test scaling policy with tight min/max

Publish values via CLI for 10–15 minutes

Collect evidence: scaling activities + ECS events

This proves the “Option A mechanics” are valid.

Phase 2 — Prove it works with Sidekiq queue depth

Either:

publish synthetic values into a separate queue dimension (safe), or

flood stage queue with safe no-op jobs

This proves your metric selection/dimensions and that the queue signal is valid.

A practical detail: target tracking needs time

Even in a test, target tracking won’t flip instantly because it relies on:

metric publishing interval

alarm evaluation window

cooldown

So when designing your test:

publish values for at least 5–10 minutes

set cooldowns lower during test

use 60-second periods

If you want, I can give you a “test harness” script

If you tell me:

your metric namespace and dimensions format (from CloudWatch)

your cluster/service names

desired min/max for a safe test (e.g., 1–4)

I’ll give you:

CLI to create a temporary target tracking policy

a bash loop that publishes metric values (high for 10 min, low for 15 min)

CLI commands to pull scaling activity and ECS events for your proof package

This ends up being a very clean customer-facing validation approach.
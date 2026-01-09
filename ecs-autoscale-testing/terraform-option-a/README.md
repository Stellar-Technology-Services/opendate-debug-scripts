## Terraform Option A (Target Tracking on custom metric) — test harness

This Terraform config creates the same setup as the CLI docs in:

- `../option-a-temp-target-tracking-policy.md`

It provisions:

- An **Application Auto Scaling scalable target** for your ECS service desired count
- A **TargetTrackingScaling policy** using a **synthetic CloudWatch metric** (`Test/Autoscaling` / `SyntheticLoad`)

### Defaults (mirrors the docs/scripts)

- **Cluster**: `opendate-stage`
- **Service**: `opendate-sidekiq`
- **Min/Max**: `2 / 4`
- **Metric**: `Test/Autoscaling` / `SyntheticLoad`
- **Dimensions**: `TestId`, `Cluster`, `Service`
- **TargetValue**: `100`
- **Cooldowns**: `60 / 60`

### Prereqs

- Terraform >= 1.14.3
- AWS credentials configured (same account/region as your ECS service)

### Apply (create the temporary policy)

From repo root:

```bash
cd ecs-autoscale-testing/terraform-option-a
terraform init
terraform apply
```

To target a different cluster, override `ecs_cluster`:

```bash
terraform apply -var='ecs_cluster=YOUR_CLUSTER_NAME'
```

To change region:

```bash
terraform apply \
  -var='aws_region=us-east-1'
```

### Drive the metric (scale out then scale in)

Use the existing publisher script from the parent folder:

```bash
cd ../..
chmod +x ./ecs-autoscale-testing/publish-metric-loop.sh
./ecs-autoscale-testing/publish-metric-loop.sh
```

### Collect proof artifacts

Use:

- `../proof-commands.md`

### Destroy (remove the temporary policy)

```bash
cd ecs-autoscale-testing/terraform-option-a
terraform destroy
```

Note: this removes the scaling policy and scalable target created by Terraform. If you changed min/max bounds for testing, destroying will remove those bounds from this Terraform-managed target; you may want to restore your “real” bounds via your normal IaC.



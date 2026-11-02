#!/usr/bin/env bash
# cost_guard.sh - List resources that can cost money while idle (current Region)
# Usage: ./cost_guard.sh
set -uo pipefail
section() { echo; echo "--- $1 ---"; }
section "EC2 instances (not terminated)"
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,InstanceType]" \
  --output table
section "NAT gateways (pending/available)"
aws ec2 describe-nat-gateways --filter "Name=state,Values=pending,available" \
  --query "NatGateways[].[NatGatewayId,State,VpcId]" --output table
section "Elastic IPs"
aws ec2 describe-addresses \
  --query "Addresses[].[PublicIp,AllocationId,AssociationId]" --output table
section "Load balancers"
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[].[LoadBalancerName,Type,State.Code]" --output table
section "VPC endpoints"
aws ec2 describe-vpc-endpoints \
  --query "VpcEndpoints[].[VpcEndpointId,VpcEndpointType,ServiceName]" --output table
section "Non-default VPCs"
aws ec2 describe-vpcs --filters "Name=is-default,Values=false" \
  --query "Vpcs[].[VpcId,CidrBlock]" --output table
section "Unattached volumes"
aws ec2 describe-volumes --filters "Name=status,Values=available" \
  --query "Volumes[].[VolumeId,Size]" --output table
section "Your AMIs and snapshots"
aws ec2 describe-images --owners self --query "Images[].[ImageId,Name]" --output table
aws ec2 describe-snapshots --owner-ids self \
  --query "Snapshots[].[SnapshotId,VolumeSize,StartTime]" --output table
section "Flow logs, log groups, alarms"
aws ec2 describe-flow-logs --query "FlowLogs[].[FlowLogId,LogGroupName]" --output table
aws logs describe-log-groups \
  --query "logGroups[].[logGroupName,retentionInDays]" --output table
aws cloudwatch describe-alarms \
  --query "MetricAlarms[].[AlarmName,StateValue]" --output table
section "S3 buckets"
aws s3 ls
echo
echo "Done. Anything listed above that you no longer need should be deleted."

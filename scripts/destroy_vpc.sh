#!/usr/bin/env bash
# destroy_vpc.sh - Delete a VPC created by build_vpc.sh
# (subnets, route tables, internet gateway, VPC). Refuses to touch untagged VPCs.
# Usage: ./destroy_vpc.sh vpc-xxxxxxxx
set -euo pipefail
VPC_ID="${1:?Usage: $0 VPC_ID}"
PROJ=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
  --query "Vpcs[0].Tags[?Key=='Project'].Value | [0]" --output text)
if [[ "$PROJ" != "vpc-lab" ]]; then
  echo "Refusing: $VPC_ID is not tagged Project=vpc-lab" >&2
  exit 1
fi
echo "Deleting subnets..."
for s in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[].SubnetId' --output text); do
  aws ec2 delete-subnet --subnet-id "$s"
done
echo "Deleting route tables..."
MAIN_RT=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
  --query 'RouteTables[0].RouteTableId' --output text)
for rt in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[].RouteTableId' --output text); do
  [[ "$rt" == "$MAIN_RT" ]] && continue
  aws ec2 delete-route-table --route-table-id "$rt"
done
echo "Deleting internet gateway..."
for igw in $(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[].InternetGatewayId' --output text); do
  aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID"
  aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
done
aws ec2 delete-vpc --vpc-id "$VPC_ID"
echo "Deleted $VPC_ID"

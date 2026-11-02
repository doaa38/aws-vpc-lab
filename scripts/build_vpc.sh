#!/usr/bin/env bash
# build_vpc.sh - Build the lab network with the AWS CLI:
# VPC, 2 public + 2 private subnets (2 AZs), internet gateway, route tables.
# Usage: ./build_vpc.sh (run in AWS CloudShell, in your lab Region)
set -euo pipefail
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-2}}"
export AWS_DEFAULT_REGION="$REGION"
PROJECT="vpc-lab"
NAME="lab-cli"
AZ_A="${REGION}a"
AZ_B="${REGION}b"
tags() { # tags RESOURCE_TYPE NAME
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=$PROJECT}]"
}
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.30.0.0/16 \
  --tag-specifications "$(tags vpc "$NAME-vpc")" \
  --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
mk_subnet() { # mk_subnet NAME CIDR AZ
  aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$2" \
    --availability-zone "$3" --tag-specifications "$(tags subnet "$1")" \
    --query Subnet.SubnetId --output text
}
PUB_A=$(mk_subnet "$NAME-public-a" 10.30.1.0/24 "$AZ_A")
PUB_B=$(mk_subnet "$NAME-public-b" 10.30.2.0/24 "$AZ_B")
PRIV_A=$(mk_subnet "$NAME-private-a" 10.30.11.0/24 "$AZ_A")
PRIV_B=$(mk_subnet "$NAME-private-b" 10.30.12.0/24 "$AZ_B")
for s in "$PUB_A" "$PUB_B"; do
  aws ec2 modify-subnet-attribute --subnet-id "$s" --map-public-ip-on-launch
done
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "$(tags internet-gateway "$NAME-igw")" \
  --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
PUB_RT=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "$(tags route-table "$NAME-public-rt")" \
  --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$PUB_RT" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" > /dev/null
PRIV_RT=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "$(tags route-table "$NAME-private-rt")" \
  --query RouteTable.RouteTableId --output text)
for s in "$PUB_A" "$PUB_B"; do
  aws ec2 associate-route-table --route-table-id "$PUB_RT" --subnet-id "$s" > /dev/null
done
for s in "$PRIV_A" "$PRIV_B"; do
  aws ec2 associate-route-table --route-table-id "$PRIV_RT" --subnet-id "$s" > /dev/null
done
echo "VPC: $VPC_ID"
echo "Public subnets: $PUB_A $PUB_B"
echo "Private subnets: $PRIV_A $PRIV_B"
echo "Internet GW: $IGW_ID"
echo "Route tables: public=$PUB_RT private=$PRIV_RT"

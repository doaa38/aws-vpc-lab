# Week 3 notes (AWS VPC)
- 2026-10-23: Region , VPC vpc-0baefb0fad0a53040 created

## CIDR plan
| Name | CIDR | AZ | Purpose |
|---|---|---|---|
| lab-vpc | 10.20.0.0/16 | - | Whole network (65,536 addresses) |
| public-a | 10.20.1.0/24 | a | Bastion, NAT gateway, load balancer node |
| public-b | 10.20.2.0/24 | b | Load balancer node (second AZ) |
| private-a | 10.20.11.0/24 | a | app-1 |
| private-b | 10.20.12.0/24 | b | app-2 |

## Ranges to avoid (already in use)
- 172.31.0.0/16 (default VPC)
- 10.10.0.0/16 and 10.11.0.0/16 (my other VPCs)
## Day 2 verification (2026-10-23)
public-a	10.20.1.0/24	us-east-2a
private-b	10.20.12.0/24	us-east-2b
private-a	10.20.11.0/24	us-east-2a
public-b	10.20.2.0/24	us-east-2b

## Day 2 - route tables (name | destinations | targets | associated subnets)
None	10.20.0.0/16	local	0
private-rt	10.20.0.0/16	local	2
public-rt	10.20.0.0/16, 0.0.0.0/0	local, igw-0ae5990409cb0f96f	2

## Day 2 - auto-assign public IPv4 (subnet | MapPublicIpOnLaunch)
public-a	True
private-b	False
private-a	False
public-b	True

## Day 2 - what I built
- Internet gateway: lab-igw, attached to lab-vpc
- public-rt: local + 0.0.0.0/0 -> lab-igw (associated with public-a, public-b)
- private-rt: local only (associated with private-a, private-b)
- Main route table: left untouched on purpose (no associations)
- Auto-assign public IPv4: enabled on public subnets only
- Resource map screenshot saved: only the 2 public subnets route to the IGW

## Day 2 - what I learned
- A subnet is public because its route table has a route to the IGW,
  not because of the auto-assign public IP setting.
- Every route table has a built-in local route, so subnets in different AZs
  can talk to each other inside the VPC.
- The most specific route wins: 10.20.x.x stays local, everything else goes to the IGW.
- The Resource map shows at a glance which subnets reach the internet gateway.

## Problems / questions
- No problems so far.

## Day 3 - Servers
- bastion: public IP <bastion-public-ip> (changes after every stop/start)
- app-1: private IP 10.20.11.185 (private-a)
- app-2: private IP 10.20.12.69 (private-b)
- Security groups: lab-bastion-sg, lab-app-sg

## Day 3 - Isolation test (from bastion to app-1)
- port 22: open (lab-app-sg allows SSH from lab-bastion-sg)
- port 80: blocked (no HTTP rule yet)
- port 3306: blocked
- ping: 100% packet loss (no ICMP rule)
- Conclusion: only SSH from the bastion reaches app-1; everything else is denied.

## Day 4 - NAT gateway, web servers, private S3 access

### NAT gateway
- Created lab-nat (Zonal mode, public-a, Public connectivity, manual Elastic IP)
- Added 0.0.0.0/0 route to the NAT in private-rt, then tested: app-1 reached the internet with the NAT's Elastic IP
- NAT gateway existed for about 60 minutes, then deleted the same day
- Removed the 0.0.0.0/0 route from private-rt, deleted the NAT, released the Elastic IP
- After deletion app-1 had no internet again (curl timed out)

### Web servers
- Installed nginx on app-1 and app-2, enabled http in firewalld, created index.html and /healthz
- Installed AWS CLI v2 on app-1 only (used to test S3)

### S3 private access
- Bucket: lab-vpc-doaa-12345 (same Region as the VPC, Block all public access ON)
- IAM policy lab-s3-access (ListBucket on the bucket, GetObject/PutObject on bucket/*)
- IAM role lab-app-role attached to app-1 (no access keys stored on the server)
- Gateway endpoint lab-s3-gw attached to private-rt only
- Result: aws s3 ls and aws s3 cp work from app-1, while curl to the internet still times out

### Challenges and what I learned
- The console now offers Regional and Zonal NAT gateways; I chose Zonal to match the design (one NAT in public-a) and keep the cost low.
- dnf install was OOM-killed ("Killed") on a t3.micro with 1 GB RAM. Fixed by creating a temporary 1 GB swapfile and installing again.
- A NAT gateway's Elastic IP cannot be released while it is still associated. I had to wait until the NAT state was Deleted, then release the IP.
- Deleting a NAT gateway does not release its Elastic IP, and an unused Elastic IP keeps billing.
- A gateway endpoint works through a route (prefix list pl-... to vpce-...) in the route table, so S3 traffic stays on the AWS network and is free.

### Experiment 2 - explicit deny
- Added inbound rule 50: SSH TCP 22 from 10.20.1.0/24, Deny, above rule 100 (Allow for the same traffic)
- ssh -o ConnectTimeout=8 app1 failed with "Connection timed out during banner exchange", even though the security group allows SSH
- A NACL evaluates rules in number order and the first match wins, so rule 50 blocked the request before rule 100 was reached
- A security group has no deny rules, so a NACL is the way to block a specific source
- Removed rule 50 and SSH worked again
- Both experiments gave the same timeout message (the first hop to the bastion works, the second hop to app-1 fails), so the symptom alone does not tell you whether the cause is a missing reply rule or an explicit deny: check both the security group and the NACL, in both directions

### VPC Flow Logs
- Created flow log lab-flow on lab-vpc: filter All, 1-minute aggregation, destination CloudWatch Logs group /lab/vpc-flow, new service role, default record format, retention 1 day
- Logs Insights query for REJECT records returned 82 matches in the last hour
- All of the 20 newest records had the bastion's private IP as the destination and public internet addresses as the source: background scanning of the bastion's public IP
- Ports probed included 23 (Telnet), 1433 (MSSQL), 27017 (MongoDB), 8080/8008/8085 (alternative web ports) and many random high ports
- Several source addresses came from the same /24 within the same minute, which suggests one scanner using multiple addresses
- These were stopped by the bastion's security group (lab-bastion-sg), which only allows SSH from my IP. The bastion subnet uses the default NACL (allow all), so the NACL did not block them
- Lesson: a REJECT record does not say whether the security group or the NACL blocked the traffic, so both have to be checked

### Top rejected sources (Logs Insights, stats by srcAddr and dstPort)
- 111 distinct (source, port) pairs were rejected in the queried window
- The only repeated pair was 157.245.56.x on port 23 (Telnet) with 7 attempts: typical scanner or botnet behaviour looking for exposed Telnet devices
- Every other pair was a single attempt on one port (for example 6379 Redis, 27017 MongoDB, 8069, 8140), which looks like wide internet scanning where one address tries one service across many IPs
- Grouping by (source, port) hides horizontal port scans from one address, so a second query grouped by source only would show which sources probe many ports

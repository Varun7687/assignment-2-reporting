# Private AWS Scheduled Reporting Server

## What this project does

This learning project sets up a private AWS server that creates a small text report, saves it in Amazon S3, and sends an email notification through Amazon SNS.

An administrator connects through a bastion host, which is a jump server. The report server stays in a private subnet and should not have a public IP address. The server uses an AWS role for permissions instead of saved access keys.

This README uses example placeholders instead of real account, network, bucket, topic, and key details. Confirm settings in AWS before describing them as complete.

## How the system works

```text
Administrator -> Bastion -> Private report server -> S3 report file
                                          └-------> SNS email notice

Private report server -> NAT Gateway -> Internet (for updates and AWS calls, if needed)
```

The NAT Gateway is meant to let the private server start outbound connections. It does not let someone on the internet start a connection into the private server. If VPC endpoints are configured for S3 or SNS, those services may use the endpoints instead of NAT. Check the AWS route tables to confirm the actual path.

## What the AWS parts mean

* VPC: the project's private network in AWS.
* Public subnet: the network area for the bastion and, if used, the NAT Gateway.
* Private subnet: the network area for the report server. It should have no public IP.
* Route table: a list that tells network traffic where to go. The public subnet normally sends internet traffic to an Internet Gateway. The private subnet may send outbound traffic to NAT.
* Security group: a firewall attached to a server. It remembers allowed connections, so reply traffic is allowed automatically.
* Network ACL: a firewall for a subnet. It does not remember connections, so rules must allow both the request and its reply.

### **Intended connection rules**

These are the planned rules, not verified AWS settings:

* Allow SSH (TCP port 22) to the bastion only from the administrator's approved IP address.
* Allow SSH to the report server only from the bastion's security group.
* Allow the report server to make outbound HTTPS connections (TCP port 443) through NAT, unless VPC endpoints provide the needed AWS access.
* Allow HTTP (TCP port 80) only if the operating system's package source needs it.
* Do not add public SSH or application access to the report server.
* For the subnet network ACL, include the reply-traffic rules too. Confirm the actual rule numbers and networks in AWS.

Before publishing, record the real VPC and subnet ranges, Availability Zones, route-table paths, security-group rules, and network ACL rules. Do not guess these values.

## Report, S3, and SNS

The report script is intended to create a text file with the date, server name, disk usage, and three clearly labeled fictional sales figures. It should:

1. Upload the file to the `reports/` folder in a private S3 bucket.
2. Send an SNS message only after the upload succeeds.
3. Put the exact S3 object name in the message.

The server's AWS role should allow only the report access the script needs: upload and read report files in that folder, and publish to the required SNS topic. It should not need permission to list every bucket or delete files. Check all policies attached to the role; one restricted policy does not rule out broader permissions from another policy.

Keep the S3 bucket private. Check that public access is blocked, encryption is on, and versioning is enabled. Confirm that the SNS email subscription has been accepted.

Do not save long-term AWS access keys on the server. If a message includes a temporary download link (a presigned URL), create a fresh one for the report. Anyone with that link may use it until it expires, so never commit it to GitHub or put it in public logs.

## Running and scheduling

The documented script path is `$HOME/assignment-2-reporting/scripts/generate_report.sh`. Check that the script is committed to the branch you plan to present, and confirm its file path and variable names before using an example like this:

```bash
AWS_REGION=YOUR_REGION \
REPORT_BUCKET=YOUR_PRIVATE_BUCKET \
SNS_TOPIC_ARN=YOUR_TOPIC_ARN \
/path/to/generate_report.sh
```

The screenshots show a draft schedule of `*/15 * * * *`. This means the job is set to run at minutes 0, 15, 30, and 45 of the server's local time. The screenshot shows the line in an editor; it does not prove the schedule was saved, installed, or run.

A simplified schedule template is:

```cron
*/15 * * * * AWS_REGION=YOUR_REGION REPORT_BUCKET=YOUR_PRIVATE_BUCKET SNS_TOPIC_ARN=YOUR_TOPIC_ARN /absolute/path/to/generate_report.sh >> /absolute/path/to/generate_report.log 2>&1
```

Use the real absolute paths and install the schedule for the correct Linux user. Run `crontab -l` to see installed schedules, then check the log and confirm a scheduled run created a report and a matching email.

### **Important: make test reports have different names**

The date-only name `reports/YYYY-MM-DD.txt` is reused every time the script runs on the same day. So running every 15 minutes can send several emails that all refer to the same object name. S3 versioning may keep older versions, but that is not the same as having three different object names.

The validation asks for at least three report objects. The date-only name is not enough to show three different objects. Add a timestamp to each name, such as `reports/YYYY-MM-DD-HHMMSS.txt`, and check that each email shows the matching name. Do not assume that older versions of the same object count as different objects; confirm with the mentor if needed.

## What the current evidence shows

The supplied screenshots show:

* SSH succeeded from the bastion to the private report server.
* A Git package installation downloaded packages and reached successful transaction-check and transaction-test messages. The screenshots cut off before the final installation result.
* The server used an assumed AWS role.
* A request to list S3 buckets was denied. This confirms that request was denied; it does not prove every permission on the role.
* Three SNS emails were received, but all show the same report object name.
* A 15-minute cron entry was displayed in an editor.

The screenshots do not yet prove:

* That direct SSH to the report server fails, or that the server has no public IP.
* That an external HTTPS request succeeds, or that NAT is the route used.
* That the package installation finished successfully.
* That three different S3 report objects exist with matching emails.
* That the cron entry was saved, installed, and ran successfully.
* The deployed VPC, subnet, route, security-group, or network ACL settings.
* The S3 public-access, encryption, and versioning settings; SNS email confirmation; or the full IAM policy attached to the server.
* That no saved AWS credentials file exists on the server.

## Checks to finish

Before saying the project is fully validated:

* Check the actual AWS region, VPC, subnets, Internet Gateway, NAT Gateway, route tables, security groups, and network ACLs.
* Confirm the report server has no public IP. Test that direct SSH fails and that SSH through the bastion works.
* On the report server, run `aws sts get-caller-identity` to confirm the assumed role. Check for AWS credentials files without printing their contents.
* Test HTTPS with `curl -I https://example.com`. A successful request proves internet reachability, but check the private route table separately to prove the path uses NAT.
* Create three uniquely named reports and confirm each S3 object matches an SNS email.
* Check the saved cron entry with `crontab -l`, then inspect the log after scheduled runs.
* Confirm the S3 settings, SNS subscription, and every policy attached to the server role.

Redact account IDs, IP addresses, server IDs, key filenames, email addresses, credentials, and live download links from screenshots before adding them to a public repository.

## Common problems: quick command checks

Replace each `YOUR_...` value with the real value. Run AWS CLI inspection commands from a terminal signed in to an AWS account with read access. Run commands marked “on the report server” after connecting to it. Do not paste AWS keys into commands or share private IPs, email addresses, or account details publicly.

### **SSH through the bastion fails**

From your computer, test the connection through the bastion:

```bash
ssh -vvv -J USER@BASTION_PUBLIC_IP USER@REPORT_SERVER_PRIVATE_IP
```

If your bastion and report server use different SSH keys, use the SSH configuration already set up for them. Do not copy a private key onto the bastion.

To check that direct SSH is not exposed, run this from outside the AWS network; it should fail or time out:

```bash
ssh -vvv -o ConnectTimeout=8 USER@REPORT_SERVER_PRIVATE_IP
```

Check whether AWS assigned the server a public IP (AWS CLI, read-only):

```bash
aws ec2 describe-instances --filters "Name=private-ip-address,Values=REPORT_SERVER_PRIVATE_IP" --query 'Reservations[].Instances[].{InstanceId:InstanceId,PublicIP:PublicIpAddress,State:State.Name}' --output table --region YOUR_REGION
```

A blank `PublicIP` is expected for the private report server. These read-only AWS CLI commands show the server security-group rules and route tables in the VPC:

```bash
aws ec2 describe-security-groups --group-ids YOUR_REPORT_SERVER_SG_ID --query 'SecurityGroups[].{Inbound:IpPermissions,Outbound:IpPermissionsEgress}' --output json --region YOUR_REGION
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=YOUR_VPC_ID" --query 'RouteTables[].{RouteTable:RouteTableId,Associations:Associations,Routes:Routes}' --output json --region YOUR_REGION
```

Check that SSH to the report server allows the bastion security group as its source, not the public internet. In the route-table output, find the table associated with the report server's subnet (or marked `Main: true`); its `0.0.0.0/0` route should point to the NAT Gateway. Also check the network ACL rules in the AWS Console, including reply traffic.

### **Package downloads or HTTPS fail**

On the report server, check whether an HTTPS request gets a response:

```bash
curl -I --connect-timeout 5 --max-time 15 https://example.com
```

Then refresh the package index using the command for the server's Linux distribution:

```bash
# Amazon Linux 2023 or RHEL
sudo dnf makecache

# Amazon Linux 2
sudo yum makecache

# Ubuntu or Debian (use this instead of dnf/yum)
sudo apt-get update
```

An HTTPS response shows that outbound access works; it does not prove the traffic used NAT. In the AWS Console, check that the private subnet's default route points to the NAT Gateway, and that the public subnet containing the NAT Gateway has a route to the Internet Gateway.

### **S3 upload is denied**

On the report server, confirm which AWS identity it is using:

```bash
aws sts get-caller-identity --region YOUR_REGION
```

Check one known report object (replace the filename with an object that exists):

```bash
aws s3api head-object --bucket YOUR_PRIVATE_BUCKET --key 'reports/EXISTING_REPORT_FILENAME.txt' --region YOUR_REGION
```

A successful response shows the object exists and this identity can read its metadata. A denied `aws s3 ls` is not the same as a failed upload: listing buckets is a separate permission and may correctly be blocked. If upload is denied, check the role, bucket policy, exact bucket/key, and encryption requirements. Confirm bucket settings with an authorized AWS CLI identity:

```bash
aws s3api get-public-access-block --bucket YOUR_PRIVATE_BUCKET --region YOUR_REGION
aws s3api get-bucket-encryption --bucket YOUR_PRIVATE_BUCKET --region YOUR_REGION
aws s3api get-bucket-versioning --bucket YOUR_PRIVATE_BUCKET --region YOUR_REGION
```

These commands show bucket-level settings. Also check account-level S3 Block Public Access and the bucket policy in the AWS Console. A missing bucket-level public-access setting alone does not tell you whether the bucket is publicly accessible.

### **SNS email is missing**

With an AWS identity allowed to inspect the topic, check whether the email subscription is confirmed:

```bash
aws sns list-subscriptions-by-topic --topic-arn YOUR_TOPIC_ARN --query 'Subscriptions[].{Protocol:Protocol,Subscription:SubscriptionArn}' --output table --region YOUR_REGION
```

`PendingConfirmation` means the recipient must accept the confirmation email. After an approved test run, check the inbox and spam folder, and confirm the email names the same S3 object that was uploaded. The command intentionally omits email addresses from its output.

### **Scheduled job does not run**

On the report server, check the current user's installed schedule and server time:

```bash
crontab -l
date
```

Check the script for shell syntax errors and confirm it is executable:

```bash
bash -n "$HOME/assignment-2-reporting/scripts/generate_report.sh"
test -x "$HOME/assignment-2-reporting/scripts/generate_report.sh" && echo "Script is executable" || echo "Script is not executable"
```

Check the log using the actual path configured in your cron line:

```bash
tail -n 50 /absolute/path/to/generate_report.log
```

If needed, check cron service logs (Amazon Linux/RHEL uses `crond`; Ubuntu/Debian commonly uses `cron`):

```bash
sudo journalctl -u crond --since "1 hour ago" --no-pager
sudo journalctl -u cron --since "1 hour ago" --no-pager
```

To test the full script manually, first make sure its report name is unique for each run. This command uploads a report and sends an SNS email, so run it only when a test upload and email are approved:

```bash
AWS_REGION=YOUR_REGION REPORT_BUCKET=YOUR_PRIVATE_BUCKET SNS_TOPIC_ARN=YOUR_TOPIC_ARN "$HOME/assignment-2-reporting/scripts/generate_report.sh"
```

## GitHub and cleanup

The GitHub screenshot used for this README showed `README.md` and `setup.sh` on `main`. Before presenting the project, confirm the branch also contains the report script, IAM policy, cron file, and any diagrams or redacted evidence screenshots you plan to reference. The architecture diagram was not present in the project files reviewed for the PDF, so add one only if you create it.

For the assignment, use the `assignment-2` branch, open a pull request to `main`, address at least one review comment, and get mentor approval before merging. Never commit passwords, AWS keys, private keys, or live download links.

NAT Gateways can cost money while they are running. Get mentor approval before deleting resources, save the required evidence, and check that billable resources are removed after approved cleanup.

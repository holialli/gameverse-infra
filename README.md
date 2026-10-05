# gameverse-infra

Terraform for the AWS + Cloudflare setup that ran [GameVerse](https://github.com/holialli/GameVerse) from March to September 2026. GameVerse has since moved to Vercel + Render, so this is kept as a reference for how the EC2 deployment was locked down, not as something that is still applied.

## What it builds

| Resource | Purpose |
|---|---|
| `aws_instance.gameverse_server` | Ubuntu 24.04 EC2 host (`t3.micro`, `ap-south-1`). The AMI is read from Canonical's public SSM parameter, so it is always the current stable image. |
| `aws_iam_role` + instance profile | Lets the instance register with Systems Manager (`AmazonSSMManagedInstanceCore`). Nothing else. |
| `aws_security_group.gameverse_sg` | Ingress on 80/443 **only from Cloudflare's published IP ranges**, fetched at plan time. No port 22. |
| `cloudflare_record.app` | Proxied A record for the apex domain, pointing at the instance. |

## Security decisions

- **No SSH.** Port 22 is never opened and no key pair is attached. Admin access and deploys went through AWS SSM Session Manager, so there were no static SSH keys to leak or rotate.
- **Origin only reachable through Cloudflare.** The security group is built from `data.cloudflare_ip_ranges`, so direct-to-IP traffic that bypasses Cloudflare's WAF and DDoS protection is dropped at the AWS edge. Re-running `terraform apply` picks up any changes to Cloudflare's ranges.
- **Least-privilege instance role.** The role only carries the SSM managed policy, so a compromised app process can't reach other AWS services through the instance credentials.
- **No secrets in the repo.** Cloudflare and AWS credentials come from the environment (`CLOUDFLARE_API_TOKEN`, the standard AWS credential chain). State, `.tfvars` and `.env` files are gitignored.
- **Drift shield.** `lifecycle.ignore_changes` on the AMI and user data stops a new Ubuntu image from silently replacing the live server on the next apply.

## What I'd change next time

- Require IMDSv2 (`metadata_options { http_tokens = "required" }`) and encrypt the root EBS volume.
- Tighten egress, which is currently open to `0.0.0.0/0`.
- Move state from the local backend to S3 with locking.
- Run Checkov or tfsec in CI on every pull request.

## Usage

```bash
export CLOUDFLARE_API_TOKEN=...   # token with DNS edit on the zone
terraform init
terraform plan
```

Requires Terraform 1.5+, AWS provider `~> 5.0` and Cloudflare provider `~> 4.0`.

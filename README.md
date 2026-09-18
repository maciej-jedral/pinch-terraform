# pinch-terraform

Infrastructure for the [Pinch](https://github.com/maciej-jedral/pinch) backend, as Terraform code.
Part of the `pinch` meta-repo as the `terraform/` submodule.

**What it builds:**

| Resource | Why |
|---|---|
| S3 bucket (`bootstrap/`) | Remote, versioned, locked Terraform state |
| EC2 `t4g.micro`, Ubuntu 24.04 arm64 | The VM that runs the backend container. First boot (`cloud-init.yaml.tftpl`) installs Docker + Compose, authorises the deploy key and creates `/opt/pinch`. The app itself is put there by `pinch-backend`'s GitHub Actions workflow, not by Terraform. |
| Elastic IP | Fixed public IP, survives stop/start |
| Security group | Inbound 22 (SSH, key-only) + 80/443 (Caddy: ACME challenge + HTTPS), all outbound |
| SSH key pair | Your `~/.ssh/pinch-aws.pub` registered with EC2; `~/.ssh/pinch-deploy.pub` (the CI deploy key) added via cloud-init |
| AWS Budgets alert | Email when gross monthly usage passes $15 (actual) / ~$20 (forecast) |
| Neon project | Free-tier managed Postgres in Frankfurt. Lives outside AWS so the data outlives the Free-plan account. |
| Porkbun DNS records | `pinchapp.fyi` + `www` → Vercel, `api.pinchapp.fyi` → the Elastic IP. The domain is registered at Porkbun (outside AWS, same reasoning as Neon); TLS is done by Caddy on the box, not here. |

Application deploy + CI live in `pinch-backend` (GitHub Actions, decided 2026-09-15); TLS is terminated by the backend container itself (decided 2026-09-18). See `ai_artifacts/ALIGNMENT.md` in the meta-repo.

## Terraform in 60 seconds

- `*.tf` files in one directory = one **module**. Terraform reads them all, order doesn't matter.
- `resource "aws_instance" "backend" { ... }` declares *what should exist*. `data "..."` blocks only *look things up*.
- `terraform plan` diffs the code against the **state** (a JSON file recording what was actually created and its real IDs) and against reality; `apply` makes the changes; `destroy` removes everything the state knows about.
- The state is the crown jewels - lose it and Terraform forgets what it built. That's why it lives in S3 (versioned) and not on a laptop.
- `variables.tf` = inputs, `terraform.tfvars` = your values for them (gitignored here), `outputs.tf` = what gets printed at the end.
- Providers (`hashicorp/aws`, `kislerdm/neon`, `jianyuan/porkbun`) are plugins that translate resources into API calls. `.terraform.lock.hcl` pins their exact versions - commit it.

## Prerequisites

Nothing installed on the host except Docker. `./tf` runs the pinned Terraform version in a container, mounting this directory and `~/.aws`.

### One-time manual setup (console clicking; cannot be automated)

1. **AWS IAM user for Terraform** (never use the root user's keys):
   IAM -> Users -> Create user `terraform` -> *Attach policies directly* -> *Create policy* -> JSON tab -> paste `iam/terraform-user-policy.json` -> name it `PinchTerraform` -> attach -> create user.
   Then: user -> *Security credentials* -> *Create access key* -> "Command Line Interface" -> download.
   Put them in `~/.aws/credentials`:
   ```ini
   [default]
   aws_access_key_id     = AKIA...
   aws_secret_access_key = ...
   ```
   and `~/.aws/config`:
   ```ini
   [default]
   region = eu-central-1
   ```
2. **Neon account + API key**: sign up at https://console.neon.tech (GitHub login is fine).
   - Org id: *Settings -> General* (looks like `org-xxxx-xxxx-12345678`) -> goes into `terraform.tfvars`.
   - API key: *Account settings -> API keys -> Create* -> goes into `.env`.
3. **SSH key**: `ssh-keygen -t ed25519 -f ~/.ssh/pinch-aws -C pinch-aws` (the public half goes into `terraform.tfvars`).
4. **Porkbun domain + API key**: buy the domain at https://porkbun.com (auto-renew is off by design - keep a calendar reminder), then *Account -> API Access -> Create API key* -> goes into `.env`; on the domain's details page switch **API Access** on. Delete the two parking records Porkbun creates (`ALIAS @` and `CNAME *` -> `pixie.porkbun.com`) - Terraform manages the records it declares, it doesn't clean up others.
5. **Vercel custom domain**: *Project -> Settings -> Domains* -> add the apex and `www` (www redirecting to apex). Vercel shows the A/CNAME targets it wants -> `vercel_apex_a` / `vercel_www_cname` in `terraform.tfvars`.

### Local config files (all gitignored)

```sh
cp .env.example .env                          # NEON_API_KEY, PORKBUN_API_KEY, PORKBUN_SECRET_KEY
cp terraform.tfvars.example terraform.tfvars  # ssh keys, budget_email, neon_org_id, vercel_*
cp backend.hcl.example backend.hcl            # bucket name - after bootstrap, see below
```

## Usage

### First time: bootstrap the state bucket

```sh
./tf -chdir=bootstrap init
./tf -chdir=bootstrap apply       # prints state_bucket_name
```

Copy the bucket name into `backend.hcl`. The bootstrap module's own state stays in `bootstrap/terraform.tfstate` (local, gitignored) - it's a single bucket, that's acceptable.

### Everything else

```sh
./tf init        # downloads providers, connects to the S3 backend
./tf plan        # dry run - always read this before apply
./tf apply       # builds it (asks for confirmation)
./tf output      # show the IP, ssh command, etc.
./tf output -raw neon_connection_uri   # the secret one
./tf destroy     # tears everything down (state bucket is protected and stays)
```

The first `apply` also triggers an email from AWS Budgets - confirm the subscription or alerts won't arrive.

**Instance replacement.** `cloud-init.yaml.tftpl` is user-data, which only runs on a brand-new instance, so `ec2.tf` sets `user_data_replace_on_change = true`: any edit to that file (or to `deploy_ssh_public_key`) makes `plan` show `aws_instance.backend must be replaced`. The Elastic IP survives; the app does not - after `apply`, update the `KNOWN_HOSTS` variable in `pinch-backend`'s `production` environment (`ssh-keyscan -t ed25519 <ip>`) and re-run the latest deploy workflow. Always `./tf plan -out=x.tfplan` first and `./tf apply x.tfplan` so you see the replacement coming.

### Verifying the VM

cloud-init takes 1-3 minutes after the instance is up. Then:

```sh
ssh -i ~/.ssh/pinch-aws ubuntu@$(./tf output -raw backend_public_ip)
cloud-init status --wait      # "done"
docker compose version
docker run --rm hello-world
# reachability of Neon from the box, without installing psql:
docker run --rm postgres:18-alpine psql "<paste ./tf output -raw neon_connection_uri>" -c 'select 1'
```

## Layout

```
tf                         wrapper: Terraform in Docker
bootstrap/main.tf          the state bucket (local state, run once)
providers.tf               Terraform/provider versions, S3 backend, provider config
variables.tf               inputs (+ terraform.tfvars.example)
ec2.tf                     VM, key pair, security group, Elastic IP
cloud-init.yaml.tftpl      first-boot template: Docker install, deploy key, /opt/pinch
budget.tf                  AWS Budgets alert
neon.tf                    Neon Postgres project
dns.tf                     Porkbun DNS records (apex + www -> Vercel, api -> EIP)
outputs.tf                 what gets printed
iam/terraform-user-policy.json   permissions for the IAM user Terraform runs as
```

## Cost (Free-plan account, Sept 2026)

~ $7/mo instance + ~ $3.65/mo public IPv4 + ~ $0.80/mo disk ≈ **$12/mo of credits**; Neon and Budgets are $0. Outside AWS: the domain, $5.66/yr at Porkbun (renewal = registration price; paid manually). The Free plan cannot bill the card; it closes at 6 months or when credits run out. Everything here is rebuilt with one `apply` on the next account - only the state bucket needs migrating (`terraform init -migrate-state`).

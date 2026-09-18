# One small VM with Docker installed, reachable on a fixed public IP.
#
# Resources, in dependency order:
#   data.aws_vpc.default  -> the account's default VPC (Step 2 replaces this with our own)
#   data.aws_ami.ubuntu   -> latest Ubuntu 24.04 LTS arm64 image, looked up by name
#   aws_key_pair          -> our SSH public key, registered with EC2
#   aws_security_group    -> the firewall: 22 (ssh) + 80/443 (Caddy: ACME + HTTPS) in, everything out
#   aws_instance          -> the VM itself, with cloud-init.yaml.tftpl as user-data
#   aws_eip (+association)-> a static public IP that survives stop/start of the instance

# ---------------------------------------------------------------------------
# Lookups (read-only "data sources", nothing is created)
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

# Canonical's official Ubuntu AMIs. The name pattern selects 24.04 (noble),
# arm64, gp3 root disk; most_recent picks the newest build.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

resource "aws_key_pair" "backend" {
  key_name   = "${var.project_name}-backend"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "backend" {
  name        = "${var.project_name}-backend"
  description = "Pinch backend: ssh + http"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.project_name}-backend"
  }
}

# Security-group rules as separate resources (AWS provider >= 5 best practice).
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.backend.id
  description       = "SSH (key auth only)"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "0.0.0.0/0"
}

# 80 is needed for Let's Encrypt's HTTP-01 challenge and for Caddy's automatic
# redirect to https; 443 is the API. Port 8000 stays inside the container
# (healthcheck only) and is not published - see pinch-backend/compose.prod.yml.
resource "aws_vpc_security_group_ingress_rule" "backend_http" {
  security_group_id = aws_security_group.backend.id
  description       = "HTTP (ACME challenge + redirect to https)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "backend_https" {
  security_group_id = aws_security_group.backend.id
  description       = "HTTPS (FrankenPHP/Caddy, auto TLS)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.backend.id
  description       = "Allow all outbound (apt, Docker Hub, Neon)"
  ip_protocol       = "-1" # all protocols
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "backend" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.backend.key_name
  vpc_security_group_ids = [aws_security_group.backend.id]

  # Runs once on first boot: installs Docker + Compose, authorises the deploy key.
  # See cloud-init.yaml.tftpl. Any change here replaces the instance.
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    deploy_ssh_public_key = var.deploy_ssh_public_key
  })
  # cloud-init only runs on a *new* instance; an in-place user_data update (the
  # provider default) would stop/start the box and silently change nothing.
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 8 # GiB
  }

  # IMDSv2 only - the modern, token-based instance metadata service.
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.project_name}-backend"
  }
}

# Elastic IP: without it the public IP changes every stop/start.
resource "aws_eip" "backend" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-backend"
  }
}

resource "aws_eip_association" "backend" {
  instance_id   = aws_instance.backend.id
  allocation_id = aws_eip.backend.id
}

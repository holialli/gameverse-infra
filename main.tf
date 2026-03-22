# 1. Fetch Cloudflare IPs for the Firewall
data "cloudflare_ip_ranges" "cloudflare" {}

# 2. Fetch Ubuntu 24.04 AMI
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# 3. Security Group (Hardened)
resource "aws_security_group" "gameverse_sg" {
  name        = "gameverse-sg-prod"
  description = "Hardened: Only allows Cloudflare and Admin SSH"

  # Allow HTTP (80) ONLY from Cloudflare
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks
  }

  # Allow HTTPS (443) ONLY from Cloudflare
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks
  }

  # SSH Restricted to your IP (Set in variables)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 4. The Server (Updated with your Swap + Docker Logic)
resource "aws_instance" "gameverse_server" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  key_name               = aws_key_pair.gameverse_ssh.key_name
  iam_instance_profile   = aws_iam_instance_profile.gameverse_profile.name
  vpc_security_group_ids = [aws_security_group.gameverse_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              # 1. Swap Space (Prevention for OOM on t3.micro)
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # 2. Docker & Dependencies
              apt-get update
              apt-get install -y docker.io curl
              systemctl start docker
              systemctl enable docker
              
               curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable metrics-server" sh -
              EOF

  tags = { Name = "GameVerse-Production" }
}

data "cloudflare_zone" "zone" {
  name = "game-verse.tech"
}

resource "cloudflare_record" "app" {
  zone_id = data.cloudflare_zone.zone.id
  name    = "@"
  value   = aws_instance.gameverse_server.public_ip
  type    = "A"
  proxied = true # The Orange Cloud!
} 

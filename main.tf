# 1. Fetch Cloudflare IPs
data "cloudflare_ip_ranges" "cloudflare" {}

# 2. Fetch Ubuntu 24.04 AMI
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# 3. IAM Role (Matching your existing AWS names)
resource "aws_iam_role" "gameverse_role" {
  name = "GameVerse_Server_Role" # Removed _Prod to match AWS

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.gameverse_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "gameverse_profile" {
  name = "GameVerse_Instance_Profile" # Removed _Prod to match AWS
  role = aws_iam_role.gameverse_role.name
}

# 4. Security Group (Updating existing group)
resource "aws_security_group" "gameverse_sg" {
  name        = "gameverse-sg" # Removed -prod to match AWS
  description = "Hardened: Only allows Cloudflare traffic"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 5. The Server (With Lifecycle Shield)
resource "aws_instance" "gameverse_server" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.gameverse_profile.name
  vpc_security_group_ids = [aws_security_group.gameverse_sg.id]

 
  lifecycle {
    ignore_changes = [
      ami,
      user_data,
      iam_instance_profile,
      key_name
    ]
  }

  tags = { Name = "GameVerse-Prod" }
}

# 6. Cloudflare Record
data "cloudflare_zone" "zone" {
  name = "game-verse.tech"
}

resource "cloudflare_record" "app" {
  zone_id = data.cloudflare_zone.zone.id
  name    = "@"
  content   = aws_instance.gameverse_server.public_ip
  type    = "A"
  proxied = true
}

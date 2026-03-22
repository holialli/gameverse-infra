variable "aws_region" {
  description = "Region for GameVerse deployment"
  default     = "ap-south-1" 
}

variable "instance_type" {
  description = "EC2 instance size"
  default     = "t3.micro"
} 

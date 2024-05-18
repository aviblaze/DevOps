variable "aws_region" {
    type = string
    default = "us-east-1"
}

variable "aws_access_id" {
  type = string
  sensitive = true
}

variable "aws_secret_key" {
    type = string
    sensitive = true
}

variable "aminamereg"{
    type = string
    default = "Amazon Linux AMI * x86_64 HVM *"
}

variable "amiowner"{
    type = string
    default = "amazon"
}

variable "subnet_id" {
    type = string
}

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

variable "iamprofilename"{
    type=string
}
variable "kms_key_name" {
    type = string
}
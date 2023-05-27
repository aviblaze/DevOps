variable "TeamName" {
  type  = string
  default = "dev"
}

variable "awsregion"{
    type = string
    default = "us-east-1"
}

variable "awsazs"{
    type = list
    default = ["us-east-1a","us-east-1b"]
}


variable "aws_access_key"{
    type = string
    sensitive = true
}

variable "aws_secret_key"{
    type = string
    sensitive = true
}

variable "vpcname"{
    type = string
    default = "MCIA-VPC"
}

variable "CIDRBlock"{
    type = string
    default = "172.2.0.0/16"
}

variable "subnetnames"{
    type = list
    default = ["MCIA-SB1","MCIA-SB2"]
}

variable "sunetCIDRblock"{
    type = list
    default = ["172.2.1.0/24","172.2.2.0/24"]
}

variable "publicsunetCIDRblock"{
    type = list
    default = ["172.2.3.0/24","172.2.4.0/24"]
}


variable "sucuritygroups"{
    type = list
    default = ["MCIA-SG"]
}

variable "aminamereg"{
    type = string
    default = "Amazon Linux AMI * x86_64 HVM *"
}

variable "amiowner"{
    type = string
    default = "amazon"
}

variable "instance_type"{
    type = string
    default = "m5.large"
}

variable "apptag"{
    type = list
    default = ["vote","result"]
}

variable "key_name"{
    type = string
    default = "MCIA-KEY"
}

variable "targetgroupnames" {
  type  = list
  default = ["MCIA-TG"]
}

variable "targetgroupports" {
  type  = list
  default = [5000,5001]
}

variable "targetgroupprotocols" {
  type  = list
  default = ["HTTP","HTTP"]
}

variable "lbports" {
  type  = list
  default = [80]
}

variable "lbprotocols" {
  type  = list
  default = ["HTTP"]
}

variable "user_data_files" {
  type = list
  default = ["launch_template_user_data_vote.sh","launch_template_user_data_result.sh"]
}
variable "path_pattern_values" {
    type = list
    default = [["/vote"],["/result"]]
}
variable "asg_min_size"{
    type = number
    default = 1
}

variable "asg_max_size"{
    type = number
    default = 1
}

variable "asg_desired_capacity"{
    type = number
    default = 1
}
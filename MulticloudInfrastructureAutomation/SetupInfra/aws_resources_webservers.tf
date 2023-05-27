data "aws_ami" "amazon-linux" {
  filter {
    name = "description"
    values = [var.aminamereg]
  }

  filter {
    name = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "owner-alias"
    values = [var.amiowner]
  }
  most_recent = true
}

data "aws_iam_role" "ec2iamprofile"{
    name = "ecsInstanceRole"
}


resource "aws_vpc" "myvpc" {
  cidr_block = "${var.CIDRBlock}"
  tags = {
    Name = "${var.vpcname}-${var.TeamName}"
  }
  count =1
}

resource "aws_subnet" "mysubnet-private" {
  vpc_id            = "${aws_vpc.myvpc[0].id}"
  cidr_block        = var.sunetCIDRblock[count.index]
  availability_zone = var.awsazs[count.index]
  count = 2
  tags = {
    Name = "${var.subnetnames[0]}-${count.index}-private"
  }

  depends_on = [ aws_vpc.myvpc ]
}

resource "aws_subnet" "mysubnet-public" {
  vpc_id            = "${aws_vpc.myvpc[0].id}"
  cidr_block        = var.publicsunetCIDRblock[count.index]
  availability_zone = var.awsazs[count.index]
  count = 2
  tags = {
    Name = "${var.subnetnames[0]}-${count.index}-public"
  }

  depends_on = [ aws_vpc.myvpc ]
}

resource "aws_eip" "myeip-natgw" {
  tags = {
	  Name = "mcia-natgw-eip${count.index}-${var.TeamName}"
  }
  count=1
  depends_on = [ aws_internet_gateway.gw ]
}

data "aws_eip" "eipnwids"{
  count = 1
  id="${aws_eip.myeip-natgw[count.index].id}"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.myvpc[0].id

  tags = {
    Name = "MCIA-GW-${var.TeamName}"
  }
  count = 1
}

resource "aws_nat_gateway" "gw" {
  allocation_id = aws_eip.myeip-natgw[count.index].id
  subnet_id     = aws_subnet.mysubnet-public[count.index].id

  tags = {
    Name = "MCIA-NATGW-${var.TeamName}-${count.index}"
  }
  count = 1
}

resource "aws_security_group" "mysg" {
  name = "${element(var.sucuritygroups, count.index)}"
  vpc_id = "${aws_vpc.myvpc[0].id}"
  
  ingress {
    description = "allow ingress http from vpc"
    protocol = "tcp"
    from_port = 5000
    to_port = 5000
    cidr_blocks = ["${var.CIDRBlock}"]
  }
  
  ingress {
    description = "acess result app from vpc"
    protocol = "tcp"
    from_port = 5001
    to_port = 5001
    cidr_blocks = ["${var.CIDRBlock}"]
  }

  ingress {
    description = "allow ssh from vpc"
    protocol = "tcp"
    from_port = 22
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow https from vpc"
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = ["${var.CIDRBlock}"]
  }

    ingress {
    description = "allow https from vpc"
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = ["${var.CIDRBlock}"]
  }

  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  count = 1
  depends_on = [ aws_vpc.myvpc ]
}

resource "aws_security_group" "mysg_lb" {
  name = "MCIA-LB-SG-${var.TeamName}"
  vpc_id = "${aws_vpc.myvpc[0].id}"
  
  ingress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  count = 1
  depends_on = [ aws_vpc.myvpc ]
}

resource "aws_route_table" "rtb-public" {
  vpc_id = aws_vpc.myvpc[0].id

  route {
    cidr_block = "0.0.0.0/0"
    #network_interface_id = data.aws_eip.eipnwids[count.index].network_interface_id
    #nat_gateway_id = aws_nat_gateway.gw[count.index].id
    gateway_id = aws_internet_gateway.gw[count.index].id
  }

  tags = {
    Name = "MCIA-RTB-${var.TeamName}-${count.index}-public"
  }

  count=1
}

resource "aws_route_table" "rtb-private" {
  vpc_id = aws_vpc.myvpc[0].id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gw[count.index].id
  }

  tags = {
    Name = "MCIA-RTB-${var.TeamName}-private"
  }

  count=1

  depends_on = [ aws_nat_gateway.gw ]
}

resource "aws_route_table_association" "rtba-private" {
  subnet_id      = aws_subnet.mysubnet-private[count.index].id
  route_table_id = aws_route_table.rtb-private[0].id
  count=2
  depends_on = [ aws_subnet.mysubnet-private, aws_route_table.rtb-private ]
}

resource "aws_route_table_association" "rtba-public" {
  subnet_id      = aws_subnet.mysubnet-public[count.index].id
  route_table_id = aws_route_table.rtb-public[0].id
  count=2
}



resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp" {
  key_name   = var.key_name      # Create a "myKey" to AWS!!
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename = "${aws_key_pair.kp.key_name}.pem"
  content = tls_private_key.pk.private_key_pem
  file_permission = "0600"
}

resource "local_file" "lt_userdata" {
  content  = <<-EOF
  #!/bin/bash
  echo ECS_CLUSTER=${aws_ecs_cluster.cluster.name} > /etc/ecs/ecs.config;
  EOF
  filename = "launch_template_user_data.sh"
}

data "template_file" "user_data_hw" {
  template = <<EOF
  #!/bin/bash
  echo ECS_CLUSTER=${aws_ecs_cluster.cluster.name} > /etc/ecs/ecs.config;
  EOF
}


resource "aws_launch_template" "mylt" {
  name = "MCIA-LT-${var.TeamName}-${count.index}"
  image_id = "ami-090310a05d8eae025"
  instance_type = "${var.instance_type}"
  key_name = "${var.key_name}"
  network_interfaces {
    associate_public_ip_address = false
    security_groups = aws_security_group.mysg.*.id
  }
  iam_instance_profile {
    name = "${data.aws_iam_role.ec2iamprofile.name}"
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "MCIA-instance"
    }
  }
  //user_data = base64encode(replace(file("launch_template_user_data.sh"),"####","${aws_ecs_cluster.cluster.name}"))
  user_data =  "${base64encode(data.template_file.user_data_hw.rendered)}"
  
  count = 1
  depends_on = [ aws_vpc.myvpc,aws_ecs_cluster.cluster,local_file.lt_userdata ]
}

resource "aws_lb_target_group" "mytg" {
    name = "${var.targetgroupnames[0]}-${count.index}"
    port = "${element(var.targetgroupports,count.index)}"
    protocol = "${element(var.targetgroupprotocols,count.index)}"
    vpc_id = "${aws_vpc.myvpc[0].id}"
    count=2
    depends_on = [ aws_vpc.myvpc ]
}

resource "aws_lb" "mylb" {
  name = "MCIA-ALB-${var.TeamName}"
  subnets = aws_subnet.mysubnet-public.*.id
  
  security_groups = ["${aws_security_group.mysg_lb[0].id}"]
  internal = false
  load_balancer_type = "application"
  count = 1
  depends_on = [ aws_vpc.myvpc ]
}

resource "aws_lb_listener" "mylblistener" {
    load_balancer_arn = "${aws_lb.mylb[0].arn}"
    port = "${var.lbports[count.index]}"
    protocol = "${var.lbprotocols[count.index]}"
    default_action {
        type = "fixed-response"
        fixed_response {
            content_type = "text/plain"
            status_code = 200
            message_body = "Success"
        }
    }
    count=1
    depends_on = [ aws_vpc.myvpc ]
}


resource "aws_lb_listener_rule" "redirect_http" {
  listener_arn = aws_lb_listener.mylblistener[0].arn

  action {
    type = "redirect"
    redirect {
      host = aws_lb.mylb[0].dns_name
      path = "/"
      port        = var.targetgroupports[count.index]
      protocol    = "${var.targetgroupprotocols[count.index]}"
      status_code = "HTTP_301"
    }
    
  }

  condition {
    path_pattern {
      values = var.path_pattern_values[count.index]
    }
  }

  count = 2
}

resource "aws_lb_listener" "mylblistener1" {
    load_balancer_arn = "${aws_lb.mylb[0].arn}"
    port = "${var.targetgroupports[count.index]}"
    protocol = "${var.targetgroupprotocols[count.index]}"
    default_action {
        type = "forward"
        target_group_arn = "${aws_lb_target_group.mytg[count.index].arn}"
        
    }
    count=2
    depends_on = [ aws_vpc.myvpc ]
}

resource "aws_sns_topic" "snstopic" {
  name = "MCIA-topic"
}

resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = aws_sns_topic.snstopic.arn
  protocol  = "email"
  endpoint  = "malla.avinash@gmail.com"
}

resource "aws_autoscaling_group" "myasg" {
    name = "MCIA_ASG${count.index}-${var.TeamName}"
    min_size = "${var.asg_min_size}"
    max_size = "${var.asg_max_size}"
    desired_capacity = "${var.asg_desired_capacity}"
    target_group_arns = aws_lb_target_group.mytg.*.arn
    vpc_zone_identifier = aws_subnet.mysubnet-private.*.id
    launch_template {
      id = "${aws_launch_template.mylt[count.index].id}"
      version = "$Latest"
    }
    count = 1
    depends_on = [ aws_vpc.myvpc ]
}

resource "aws_autoscaling_notification" "example_notifications" {
  group_names = [
    aws_autoscaling_group.myasg[count.index].name
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.snstopic.arn
  count=1
}


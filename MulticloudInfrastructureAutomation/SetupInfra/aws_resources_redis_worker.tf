
data "aws_iam_role" "taskrole"{
    name = "ecsTaskExecutionRole"
}

resource "aws_launch_template" "mycp" {
  name = "MCIA-LT-CP-${var.TeamName}-${count.index}"
  image_id = "ami-0ebb9b1c37ef501ab"
  instance_type = "${var.instance_type}"
  key_name = aws_key_pair.kp.key_name
  network_interfaces {
    associate_public_ip_address = true
    security_groups = aws_security_group.mysg.*.id
  }
  iam_instance_profile {
    name = "${data.aws_iam_role.ec2iamprofile.name}"
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "MCIA-instance-CP-${count.index}"
    }
  }

  user_data = <<-EOF
        #!/bin/bash
        echo ECS_CLUSTER=${aws_ecs_cluster.cluster.name} >> /etc/ecs/ecs.config
        EOF
  count = 0
  depends_on = [ aws_vpc.myvpc ]
}

resource "aws_autoscaling_group" "myasgcp" {
    name = "MCIA_ASG-CP-${count.index}-${var.TeamName}"
    min_size = "${var.asg_min_size}"
    max_size = "${var.asg_max_size}"
    desired_capacity = "${var.asg_desired_capacity}"
    vpc_zone_identifier = aws_subnet.mysubnet-private.*.id
    launch_template {
      id = "${aws_launch_template.mycp[0].id}"
      version = "$Latest"
    }
    count = 0
    depends_on = [ aws_vpc.myvpc ]
}

resource "aws_ecs_cluster" "cluster" {
  name = "mcia-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "clusterCP" {
  cluster_name = aws_ecs_cluster.cluster.name
  capacity_providers = ["FARGATE","FARGATE_SPOT"]
  count=1
}

resource "aws_instance" "clustInstance" {
  ami = "ami-0ebb9b1c37ef501ab"
  instance_type = "${var.instance_type}"
  vpc_security_group_ids = [ "${element(aws_security_group.mysg.*.id, count.index)}" ]
  key_name = aws_key_pair.kp.key_name
  subnet_id = "${element(aws_subnet.mysubnet-private.*.id, count.index)}"
  tags = {
      Name = "MCIA-instance-ECS-${count.index}"
      app = "${element(var.apptag, count.index)}"
  }
  iam_instance_profile = data.aws_iam_role.ec2iamprofile.name
  associate_public_ip_address = true
  user_data = <<-EOF
      #!/bin/bash
      echo ECS_CLUSTER=${aws_ecs_cluster.cluster.name} >> /etc/ecs/ecs.config
      EOF
  count = 0
  depends_on = [ aws_vpc.myvpc ]
}

resource "aws_ecs_task_definition" "taskdefinition" {
  family = "mcia-taskdefinition"
  network_mode = "bridge"
  container_definitions = jsonencode([
    {
      name      = "vote"
      image     = "dockersamples/examplevotingapp_vote"
      cpu       = 10
      memory    = 256
      links = ["redis"]
      portMappings = [
        {
          "name" = "vote-80-tcp",
          "containerPort" = 80,
          "hostPort" = 5000,
          "protocol" = "tcp",
          "appProtocol" = "http"
        }
      ]
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = "/ecs/mcia-taskdefinition"
          awslogs-region        = var.awsregion
          awslogs-create-group =  "true",
          awslogs-stream-prefix = "ecs"
        }
      }
    },
    {
      name      = "redis"
      image     = "redis:alpine"
      cpu       = 10
      memory    = 256
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = "/ecs/mcia-taskdefinition"
          awslogs-region        = var.awsregion
          awslogs-create-group =  "true",
          awslogs-stream-prefix = "ecs"
        }
      }
    },
    {
      name      = "worker"
      image     = "mallaavinash/customdb_worker:v4"
      cpu       = 10
      memory    = 512
      essential = true
      environment = [
        {
          name  = "DB_CONNECTION_STRING"
          value = "Server=${azurerm_postgresql_server.psqlserver.fqdn};Database=postgres;Username=${var.postgresdb_user}@${azurerm_postgresql_server.psqlserver.name};Password=${var.postgresdb_password};Database=postgres;"
        }
      ]
      links = ["redis"]
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = "/ecs/mcia-taskdefinition"
          awslogs-region        = var.awsregion
          awslogs-create-group =  "true",
          awslogs-stream-prefix = "ecs"
        }
      }
    },
    {
      name      = "result"
      image     = "mallaavinash/customdb_result:v3"
      cpu       = 10
      memory    = 256
      essential = true
      portMappings = [
        {
          "name" = "result-80-tcp",
          "containerPort" = 80,
          "hostPort" = 5001,
          "protocol" = "tcp",
          "appProtocol" = "http"
        }
      ]
      environment = [
        {
          name  = "SERVER"
          value = "${azurerm_postgresql_server.psqlserver.fqdn}"
        },
        {
          name  = "USERNAME"
          value = "${var.postgresdb_user}@${azurerm_postgresql_server.psqlserver.name}"
        },
        {
          name  = "DB"
          value = "postgres"
        },
        {
          name  = "PASS"
          value = "${var.postgresdb_password}"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = "/ecs/mcia-taskdefinition"
          awslogs-region        = var.awsregion
          awslogs-create-group =  "true",
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
  
  requires_compatibilities = ["EC2"]
  task_role_arn=data.aws_iam_role.taskrole.arn
  execution_role_arn = data.aws_iam_role.ec2iamprofile.arn
}

resource "aws_ecs_service" "service" {
  name            = "mcia-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.taskdefinition.arn
  desired_count   = 1
  launch_type     = "EC2"
}

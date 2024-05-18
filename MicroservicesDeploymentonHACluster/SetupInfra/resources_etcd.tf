locals {
  subnet_cidr=["10.0.1.0/24","10.0.2.0/24","10.0.3.0/24"]
  private_ip = ["10.0.1.4","10.0.2.4","10.0.3.4"]
  master_private_ip = ["10.0.1.5","10.0.2.5","10.0.3.5"]
  worker_private_ip = ["10.0.1.6","10.0.2.6","10.0.3.6"]
  ETCD_VERSION="v3.5.0"
  ETCD_CONFIG="/etc/etcd"
  certs=["ca.crt","ca.key"]
  kube_cidr="10.2.0.0/16"
}

data "aws_availability_zones" "avZoneslist" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  filter {
    name = "region-name"
    values = [ var.aws_region ]
  }
}

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

data "template_file" "user_data_etcd" {
  template = <<-EOF
  #!/bin/bash
  hostnamectl set-hostname h8-k8s-etcd-${count.index}
  mkdir -p /etc/ssl/etcd
  aws s3 cp s3://ha-k8s-etcd-certs/ca.crt /etc/ssl/etcd/ca.crt
  aws s3 cp s3://ha-k8s-etcd-certs/ca.key /etc/ssl/etcd/ca.key

  PEER_FQDN=$(hostname --fqdn)
  PEER_IP=${local.private_ip[count.index]}
  printf "[req]
  req_extensions = v3_req
  distinguished_name = req_distinguished_name
  [req_distinguished_name]
  [ v3_req ]
  basicConstraints = CA:FALSE
  keyUsage = nonRepudiation, digitalSignature, keyEncipherment
  extendedKeyUsage = clientAuth,serverAuth
  subjectAltName = IP:%s, DNS:%s
  " $PEER_IP $PEER_FQDN > /etc/ssl/etcd/openssl.cnf
  openssl genrsa -out /etc/ssl/etcd/etcd.key 2048
  useradd -U -s /bin/false etcd
  chmod 600 etcd.key
  chown etcd:etcd etcd.key
  chown -R etcd:etcd /etc/ssl/etcd

  openssl req -new -key /etc/ssl/etcd/etcd.key -out /etc/ssl/etcd/etcd.csr -subj "/CN=$(hostname)" -extensions v3_req -config /etc/ssl/etcd/openssl.cnf -sha256
  openssl x509 -req -CA /etc/ssl/etcd/ca.crt -CAkey /etc/ssl/etcd/ca.key -CAcreateserial -in /etc/ssl/etcd/etcd.csr -out /etc/ssl/etcd/etcd.crt -days 365 -extensions v3_req -extfile /etc/ssl/etcd/openssl.cnf -sha256
  cat ./ssl/ca.crt >> ./ssl/etcd.crt
  
  mkfs -t ext4 /dev/xvdh
  mkdir -p /opt/etcd
  mount /dev/xvdh /opt/etcd


  ETCD_URL="https://github.com/coreos/etcd/releases/download/${local.ETCD_VERSION}/etcd-${local.ETCD_VERSION}-linux-amd64.tar.gz"

  wget $ETCD_URL -O /tmp/etcd-${local.ETCD_VERSION}-linux-amd64.tar.gz
  tar -xzf /tmp/etcd-${local.ETCD_VERSION}-linux-amd64.tar.gz -C /tmp
  install --owner root --group root --mode 0755 /tmp/etcd-${local.ETCD_VERSION}-linux-amd64/etcd /usr/bin/etcd
  install --owner root --group root --mode 0755 /tmp/etcd-${local.ETCD_VERSION}-linux-amd64/etcdctl /usr/bin/etcdctl
  install -d --owner root --group root --mode 0755 ${local.ETCD_CONFIG}

  chmod 755 /usr/bin/etcd
  chmod 755 /usr/bin/etcdctl
  
  chown etcd:etcd /usr/bin/etcd
  chown etcd:etcd /usr/bin/etcdctl

  mkdir -p /opt/etcd/data
  mkdir -p /opt/etcd/wal
  mkdir -p /etc/etcd
  chown -R etcd:etcd /opt/etcd
  chown -R etcd:etcd /etc/etcd

  PRIMARY_HOST_IP=${local.private_ip[count.index]}

  printf "ETCD_NAME=h8-k8s-etcd-${count.index}
  ETCD_DATA_DIR=/opt/etcd/data
  ETCD_WAL_DIR=/opt/etcd/wal
  ETCD_LISTEN_PEER_URLS=https://%s:2380
  ETCD_INITIAL_ADVERTISE_PEER_URLS=https://%s:2380
  ETCD_PEER_CERT_FILE=/etc/ssl/etcd/etcd.crt
  ETCD_PEER_KEY_FILE=/etc/ssl/etcd/etcd.key
  ETCD_PEER_TRUSTED_CA_FILE=/etc/ssl/etcd/ca.crt
  ETCD_PEER_CLIENT_CERT_AUTH=true
  ETCD_LISTEN_CLIENT_URLS=http://127.0.0.1:2379,https://%s:2379
  ETCD_ADVERTISE_CLIENT_URLS=https://%s:2379
  ETCD_CERT_FILE=/etc/ssl/etcd/etcd.crt
  ETCD_KEY_FILE=/etc/ssl/etcd/etcd.key
  ETCD_TRUSTED_CA_FILE=/etc/ssl/etcd/ca.crt
  ETCD_CLIENT_CERT_AUTH=true
  ETCD_INITIAL_CLUSTER=h8-k8s-etcd-0=https://${local.private_ip[0]}:2380,h8-k8s-etcd-1=https://${local.private_ip[1]}:2380,h8-k8s-etcd-2=https://${local.private_ip[2]}:2380
  ETCD_HEARTBEAT_INTERVAL=800
  ETCD_ELECTION_TIMEOUT=4000
  " $PRIMARY_HOST_IP $PRIMARY_HOST_IP $PRIMARY_HOST_IP $PRIMARY_HOST_IP > /etc/etcd/options.env

  cat > /etc/systemd/system/etcd.service << EOF1
  [Unit]
  Description=etcd

  [Service]
  User=etcd
  Type=notify
  EnvironmentFile=/etc/etcd/options.env
  ExecStart=/usr/bin/etcd
  Restart=always
  RestartSec=10s
  LimitNOFILE=40000
  TimeoutStartSec=0

  [Install]
  WantedBy=multi-user.target
  EOF1

  export ETCDCTL_API=3

  systemctl enable etcd
  systemctl start etcd

  aws s3 cp /etc/ssl/etcd/etcd.crt s3://ha-k8s-etcd-certs/etcd${count.index}.crt
  aws s3 cp /etc/ssl/etcd/etcd.key s3://ha-k8s-etcd-certs/etcd${count.index}.key

  EOF
  count = 3
}

resource "aws_vpc" "ha-k8s-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    "Name" = "ha-k8s-vpc"
    "essential" = "true" 
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.ha-k8s-vpc.id

  ingress {
    protocol  = -1
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_route_table" "ha-k8s-rt" {
  vpc_id = aws_vpc.ha-k8s-vpc.id
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.ha-k8s-igw[0].id
  }
  tags = {
    "Name" = "ha-k8s-rt"
    "essential" = "true"
  }
  depends_on = [ aws_vpc.ha-k8s-vpc,aws_internet_gateway.ha-k8s-igw ]
}

resource "aws_route_table_association" "ha-k8s-rt-assc" {
  route_table_id = aws_route_table.ha-k8s-rt.id
  subnet_id = aws_subnet.ha-k8s-subnets[count.index].id
  count = 3
  depends_on = [aws_vpc.ha-k8s-vpc,aws_route_table.ha-k8s-rt,aws_subnet.ha-k8s-subnets]
}



resource "aws_subnet" "ha-k8s-subnets" {
    
    cidr_block = local.subnet_cidr[count.index]
    vpc_id = aws_vpc.ha-k8s-vpc.id
    availability_zone = data.aws_availability_zones.avZoneslist.names[count.index]
    tags = {
      "Name" = "k8s-subnet-${count.index}"
    }
    count=3
    depends_on = [ aws_vpc.ha-k8s-vpc,data.aws_availability_zones.avZoneslist ]
}

resource "aws_internet_gateway" "ha-k8s-igw"{

    vpc_id = aws_vpc.ha-k8s-vpc.id
    tags = {
        "Name" = "ha-k8s-igw" 
    }
    depends_on = [ aws_vpc.ha-k8s-vpc ]
    count=1
}

resource "aws_ebs_volume" "ha-k8s-etcd-ebs" {
  availability_zone = data.aws_availability_zones.avZoneslist.names[count.index]
  size              = 40

  tags = {
    Name = "ha-k8s-etcd-ebs-${count.index}"
  }
  count =3
}

resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp" {
  key_name   = "ha-k8s-key.pem"
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename = "ha-k8s-key.pem"
  content = tls_private_key.pk.private_key_pem
  file_permission = "0600"
}

resource "aws_s3_bucket" "ha-k8s-etcd-certs" {

  bucket = "ha-k8s-etcd-certs"
  tags = {
    Name = "ha-k8s-etcd-certs"
  }
  force_destroy = true
}

resource "aws_s3_object" "certs" {
  bucket = aws_s3_bucket.ha-k8s-etcd-certs.id
  key    = local.certs[count.index]
  source = "./ssl/${local.certs[count.index]}"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = filemd5("./ssl/${local.certs[count.index]}")
  count=2
  depends_on = [ aws_s3_bucket.ha-k8s-etcd-certs ]
}


resource "aws_s3_object" "upload-files" {
  for_each = fileset("./kube-deployments/", "**")
  bucket = aws_s3_bucket.ha-k8s-etcd-certs.id
  key = "kube-deployments/${each.value}"
  source = "./kube-deployments/${each.value}"
  etag = filemd5("./kube-deployments/${each.value}")
  depends_on = [ aws_s3_bucket.ha-k8s-etcd-certs ]
}

resource "aws_instance" "h8-k8s-etcd" {
    //name = "h8-k8s-etcd-${count.index}"
    subnet_id = aws_subnet.ha-k8s-subnets[count.index].id
    //ami = data.aws_ami.amazon-linux.id
    ami = "ami-0715c1897453cabd1"
    instance_type = "t2.small"
    key_name = aws_key_pair.kp.key_name
    iam_instance_profile = data.aws_iam_role.ec2iamprofile.id
    associate_public_ip_address = true
    user_data = "${base64encode(data.template_file.user_data_etcd[count.index].rendered)}"
    tags = {
        "Name" = "h8-k8s-etcd-${count.index}"
    }
    private_dns_name_options {
        hostname_type = "resource-name"
    }
    private_ip = local.private_ip[count.index]
    count = 3
    depends_on = [ aws_ebs_volume.ha-k8s-etcd-ebs,aws_s3_object.certs]
}

resource "aws_volume_attachment" "ebs_att" {
    device_name = "/dev/sdh"
    volume_id   = aws_ebs_volume.ha-k8s-etcd-ebs[count.index].id
    instance_id = aws_instance.h8-k8s-etcd[count.index].id
    count=3
    depends_on = [ aws_instance.h8-k8s-etcd ]
}


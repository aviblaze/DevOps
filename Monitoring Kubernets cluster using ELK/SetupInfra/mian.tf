data "template_file" "user_data_setupminikube" {
  template = <<-EOF
    #!/bin/bash
    sudo -u ec2-user -i <<'EOF1'
    sudo yum -y update
    sudo yum -y install docker
    sleep 30
    sudo usermod -a -G docker ec2-user
    newgrp docker
    sudo systemctl start docker
    sudo systemctl enable docker

    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    kubectl version --client

    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    minikube start --cpus 4 --memory 8192
    sleep 300
    kubectl cluster-info
    minikube status

    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
    helm version

    helm repo add elastic https://helm.elastic.co
    helm repo update

    aws s3 cp s3://kubefiles/kube-files /home/ec2-user/kube-files --recursive

    sudo chown -R ec2-user:ec2-user /home/ec2-user/kube-files
    cd /home/ec2-user/kube-files
    helm dependency update
    cd ..
    helm install myapp ./kube-files
    
    sleep 360
    helm install kibana elastic/kibana --values /home/ec2-user/kube-files/kibana-values.yaml
    sleep 360
    kubectl port-forward --address 0.0.0.0 svc/kibana-kibana 5601:5601 &
    EOF1

  EOF
}

data "aws_iam_role" "ec2iamprofile"{
    name = var.iamprofilename
}

resource "aws_s3_bucket" "kubefiles" {

  bucket = "kubefiles"
  tags = {
    Name = "kubefiles"
  }
  force_destroy = true
}

resource "aws_s3_object" "upload-kubefiles" {
  for_each = fileset("../kube-files/", "**")
  bucket = aws_s3_bucket.kubefiles.id
  key = "kube-files/${each.value}"
  source = "../kube-files/${each.value}"
  etag = filemd5("../kube-files/${each.value}")
  depends_on = [ aws_s3_bucket.kubefiles ]
}


resource "aws_instance" "h8-k8s-worker" {

    ami = "ami-0715c1897453cabd1"
    instance_type = "c4.2xlarge"
    key_name = var.kms_key_name
    iam_instance_profile = data.aws_iam_role.ec2iamprofile.id
    associate_public_ip_address = true
    root_block_device {
      volume_size = 50
      delete_on_termination = true
    }
    user_data = "${base64encode(data.template_file.user_data_setupminikube.rendered)}"
    tags = {
        "Name" = "Minikube-cluster"
    }
    count = 1
}
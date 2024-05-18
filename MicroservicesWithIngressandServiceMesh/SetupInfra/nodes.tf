data "aws_iam_role" "ec2iamprofile"{
    name = "ecsInstanceRole"
}

data "template_file" "user_data_node" {
  template = <<-EOF
#!/bin/bash
sudo echo "${count.index}" > /tmp/count.conf
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo swapoff -a

sudo yum update -y
cat <<EOF1 | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF1

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF2 | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF2

sudo sysctl --system
sudo yum update -y && sudo yum install -y containerd
sudo mkdir -p /etc/containerd

containerd config default | sudo tee /etc/containerd/config.toml

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
#sudo systemctl status containerd

cat <<EOF1 | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF1

sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl start containerd
sudo systemctl start kubelet
sudo systemctl enable --now kubelet
sudo systemctl daemon-reload

if [ ${count.index} -eq 0 ]
then

  TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
  IPADDR=$(curl -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/meta-data/public-ipv4)
  NODENAME=$(hostname -s)
  POD_CIDR="192.168.0.0/16"

  #sudo kubeadm init --control-plane-endpoint=$IPADDR  --apiserver-cert-extra-sans=$IPADDR  --pod-network-cidr=$POD_CIDR --node-name $NODENAME --ignore-preflight-errors Swap
  sudo kubeadm init --control-plane-endpoint=$IPADDR --pod-network-cidr=$POD_CIDR --ignore-preflight-errors Swap
  # configure kubeconfig for kubectl
  sudo mkdir -p /root/.kube
  sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
  sudo chown $(id -u):$(id -g) /root/.kube/config

  sudo mkdir -p /home/ec2-user/.kube
  sudo cp -i /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
  sudo chown -R ec2-user:ec2-user /home/ec2-user/.kube

  sudo mkdir -p /home/ssm-user/.kube
  sudo cp -i /etc/kubernetes/admin.conf /home/ssm-user/.kube/config
  sudo chown -R ssm-user:ssm-user /home/ssm-user/.kube

  # install calico
  sudo kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
  sudo curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml -O
  sudo kubectl create -f custom-resources.yaml

  sudo kubectl taint nodes --all node-role.kubernetes.io/control-plane-
  sudo kubectl taint nodes --all node-role.kubernetes.io/master-

  sudo echo "$(kubeadm token create)"  |sudo aws s3 cp - s3://ha-k8s-master-details/jointoken.txt
  sudo echo "$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')" |sudo  aws s3 cp - s3://ha-k8s-master-details/jointokenhash.txt
  sudo echo "$IPADDR" | sudo aws s3 cp - s3://ha-k8s-master-details/masterip.txt

  sleep 300

  mkdir /home/ssm-user/kube-deployments
  sudo aws s3 cp s3://ha-k8s-master-details/kube-deployments /home/ssm-user/kube-deployments --recursive


  sudo kubectl apply -f /home/ssm-user/kube-deployments/ngnix-deploy.yaml
  kubectl wait --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=240s

  kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission
  sudo kubectl apply -f /home/ssm-user/kube-deployments/ngnix-ingress.yaml

  sudo kubectl apply -f /home/ssm-user/kube-deployments/App/


else
  sleep 180
  touch /tmp/timeout

  TOKEN=$(sudo aws s3 cp s3://ha-k8s-master-details/jointoken.txt -)
  TOKEN_HASH=$(sudo aws s3 cp s3://ha-k8s-master-details/jointokenhash.txt -)
  MASTER_IP=$(sudo aws s3 cp s3://ha-k8s-master-details/masterip.txt - | tr -d '[:space:]')

  sudo kubeadm join $MASTER_IP:6443 --token $TOKEN --discovery-token-ca-cert-hash sha256:$TOKEN_HASH
  # configure kubeconfig for kubectl
  sudo mkdir -p /root/.kube
  sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
  sudo chown $(id -u):$(id -g) /root/.kube/config

  sudo mkdir -p /home/ec2-user/.kube
  sudo cp -i /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
  sudo chown -R ec2-user:ec2-user /home/ec2-user/.kube

  sudo mkdir -p /home/ssm-user/.kube
  sudo cp -i /etc/kubernetes/admin.conf /home/ssm-user/.kube/config
  sudo chown -R ssm-user:ssm-user /home/ssm-user/.kube

fi
  EOF
  count = 3
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

resource "aws_s3_bucket" "ha-k8s-master-details" {

  bucket = "ha-k8s-master-details"
  tags = {
    Name = "ha-k8s-master-details"
  }
  force_destroy = true
}


resource "aws_s3_object" "upload-files" {
  for_each = fileset("../kube-deployments/", "**")
  bucket = aws_s3_bucket.ha-k8s-master-details.id
  key = "kube-deployments/${each.value}"
  source = "../kube-deployments/${each.value}"
  etag = filemd5("../kube-deployments/${each.value}")
  depends_on = [ aws_s3_bucket.ha-k8s-master-details ]
}

# resource "aws_s3_object" "upload-files1" {
#   for_each = fileset("../kube-deployments/App", "**")
#   bucket = aws_s3_bucket.ha-k8s-master-details.id
#   key = "kube-deployments/App/${each.value}"
#   source = "../kube-deployments/App/${each.value}"
#   etag = filemd5("../kube-deployments/App/${each.value}")
#   depends_on = [ aws_s3_bucket.ha-k8s-master-details ]
# }

resource "aws_instance" "h8-k8s-node" {

    subnet_id = var.subnet_id
    ami = "ami-051f7e7f6c2f40dc1"
    instance_type = "t2.medium"
    key_name = aws_key_pair.kp.key_name
    iam_instance_profile = data.aws_iam_role.ec2iamprofile.id
    associate_public_ip_address = true
    source_dest_check = false
    user_data = "${base64encode(data.template_file.user_data_node[count.index].rendered)}"
    tags = {
        "Name" = "h8-k8s-node-${count.index}"
    }
    private_dns_name_options {
        hostname_type = "resource-name"
    }
    count = 3
}


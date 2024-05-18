data "template_file" "user_data_worker" {
  template = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname h8-k8s-worker-${count.index}

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

    sudo yum install -y containerd
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml

    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    echo "${local.worker_private_ip[count.index]}   h8-k8s-worker-${count.index}" | sudo tee -a /etc/hosts

    sudo systemctl restart containerd
    sudo systemctl status containerd

    sudo swapoff -a

    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    sudo yum update -y && sudo yum install -y ca-certificates

    cat <<EOF3 | sudo tee /etc/yum.repos.d/kubernetes.repo
    [kubernetes]
    name=Kubernetes
    baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
    enabled=1
    gpgcheck=1
    gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
    exclude=kubelet kubeadm kubectl
    EOF3

    # Set SELinux in permissive mode (effectively disabling it)
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

    sudo yum install -y kubelet-1.27.0 kubeadm-1.27.0 kubectl-1.27.0 --disableexcludes=kubernetes

    sudo systemctl start containerd
    sudo systemctl start kubelet
    sudo systemctl enable kubelet
    sudo systemctl daemon-reload

    sleep 180
    TOKEN=$(sudo aws s3 cp s3://ha-k8s-etcd-certs/jointoken.txt -)
    TOKEN_HASH=$(sudo aws s3 cp s3://ha-k8s-etcd-certs/jointokenhash.txt -)

    sudo kubeadm join ${aws_lb.ha-k8s-lb[0].dns_name}:6443 --token $TOKEN --discovery-token-ca-cert-hash sha256:$TOKEN_HASH --ignore-preflight-errors=all
    # configure kubeconfig for kubectl
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config
    chown $(id -u):$(id -g) /root/.kube/config

  EOF
  count = 3
}

resource "aws_instance" "h8-k8s-worker" {

    subnet_id = aws_subnet.ha-k8s-subnets[count.index].id
    ami = "ami-0715c1897453cabd1"
    instance_type = "t2.small"
    key_name = aws_key_pair.kp.key_name
    iam_instance_profile = data.aws_iam_role.ec2iamprofile.id
    associate_public_ip_address = true
    user_data = "${base64encode(data.template_file.user_data_worker[count.index].rendered)}"
    tags = {
        "Name" = "h8-k8s-worker-${count.index}"
    }
    private_dns_name_options {
        hostname_type = "resource-name"
    }
    private_ip = local.worker_private_ip[count.index]
    count = 3
    depends_on = [ aws_instance.h8-k8s-etcd,aws_instance.h8-k8s-master,aws_lb.ha-k8s-lb]
}
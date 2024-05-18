data "template_file" "user_data_master" {
  template = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname h8-k8s-master-${count.index}
    
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
    echo "${local.master_private_ip[count.index]}   h8-k8s-master-${count.index}" | sudo tee -a /etc/hosts

    sudo systemctl restart containerd
    sudo systemctl status containerd

    sudo swapoff -a

    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    sudo yum install -y ca-certificates curl

    sudo cat <<EOF3 | tee /etc/yum.repos.d/kubernetes.repo
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

    sudo apt-get install -y apt-transport-https ca-certificates curl
    sudo yum install -y kubelet-1.27.0 kubeadm-1.27.0 kubectl-1.27.0 --disableexcludes=kubernetes
    
    sudo systemctl start containerd
    sudo systemctl start kubelet
    sudo systemctl enable kubelet
    sudo systemctl daemon-reload

    sudo echo "${count.index}" > /tmp/count.conf

    if [ ${count.index} -eq 0 ]
    then

      mkdir -p /etc/kubernetes/pki/etcd

      sudo aws s3 cp s3://ha-k8s-etcd-certs/ca.crt /etc/kubernetes/pki/etcd/ca.crt
      sudo aws s3 cp s3://ha-k8s-etcd-certs/ca.key /etc/kubernetes/pki/etcd/ca.key
      sudo aws s3 cp s3://ha-k8s-etcd-certs/etcd${count.index}.crt /etc/kubernetes/pki/etcd/etcd.crt
      sudo aws s3 cp s3://ha-k8s-etcd-certs/etcd${count.index}.key /etc/kubernetes/pki/etcd/etcd.key

      sudo printf 'apiVersion: kubeadm.k8s.io/v1beta3\nkind: ClusterConfiguration\nkubernetesVersion: stable\napiServer:\n  certSANs:\n  - "${aws_lb.ha-k8s-lb[0].dns_name}"\ncontrolPlaneEndpoint: "${aws_lb.ha-k8s-lb[0].dns_name}:6443"\netcd:\n  external:\n    endpoints:\n    - https://${local.private_ip[count.index]}:2379\n    caFile: /etc/kubernetes/pki/etcd/ca.crt\n    certFile: /etc/kubernetes/pki/etcd/etcd.crt\n    keyFile: /etc/kubernetes/pki/etcd/etcd.key\nnetworking:\n  podSubnet: "192.168.0.0/16"' > /tmp/kubeadm-config.yaml
      sudo kubeadm init --config  /tmp/kubeadm-config.yaml --ignore-preflight-errors=all

      # configure kubeconfig for kubectl
      sudo mkdir -p /root/.kube
      sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
      sudo chown $(id -u):$(id -g) /root/.kube/config

      sudo mkdir -p /home/ec2-user/.kube
      sudo cp -i /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
      sudo chown $(id -u):$(id -g) /home/ec2-user/.kube/config

      sudo mkdir -p /home/ssm-user/.kube
      sudo cp -i /etc/kubernetes/admin.conf /home/ssm-user/.kube/config
      sudo chown $(id -u):$(id -g) /home/ssm-user/.kube/config
      
      # install calico
      sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
      sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

      sudo kubectl taint nodes --all node-role.kubernetes.io/control-plane-
      sudo kubectl taint nodes --all node-role.kubernetes.io/master-

      sudo echo "$(kubeadm token create)"  | aws s3 cp - s3://ha-k8s-etcd-certs/jointoken.txt
      sudo echo "$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')" | aws s3 cp - s3://ha-k8s-etcd-certs/jointokenhash.txt
      sudo aws s3 cp /etc/kubernetes/pki/ca.crt s3://ha-k8s-etcd-certs/master-ca.crt 
      sudo aws s3 cp /etc/kubernetes/pki/ca.key s3://ha-k8s-etcd-certs/master-ca.key
      sudo aws s3 cp /etc/kubernetes/pki/sa.key s3://ha-k8s-etcd-certs/sa.key
      sudo aws s3 cp /etc/kubernetes/pki/sa.pub s3://ha-k8s-etcd-certs/sa.pub
      sudo aws s3 cp /etc/kubernetes/pki/front-proxy-ca.crt s3://ha-k8s-etcd-certs/front-proxy-ca.crt
      sudo aws s3 cp /etc/kubernetes/pki/front-proxy-ca.key s3://ha-k8s-etcd-certs/front-proxy-ca.key

      sleep 300
      mkdir /home/ssm-user/kube-deployments
      sudo aws s3 cp s3://ha-k8s-etcd-certs/kube-deployments/db-deployment.yaml /home/ssm-user/kube-deployments/
      sudo aws s3 cp s3://ha-k8s-etcd-certs/kube-deployments/db-service.yaml /home/ssm-user/kube-deployments/
      sudo aws s3 cp s3://ha-k8s-etcd-certs/kube-deployments/redis-deployment.yaml /home/ssm-user/kube-deployments/
      sudo aws s3 cp s3://ha-k8s-etcd-certs/kube-deployments/redis-service.yaml /home/ssm-user/kube-deployments/
      sudo aws s3 cp s3://ha-k8s-etcd-certs/kube-deployments/result-deployment.yaml /home/ssm-user/kube-deployments/
      sudo aws s3 cp s3://ha-k8s-etcd-certs/kube-deployments/result-service.yaml /home/ssm-user/kube-deployments/
      sudo aws s3 cp s3://ha-k8s-etcd-certs/kube-deployments/vote-deployment.yaml /home/ssm-user/kube-deployments/
      sudo aws s3 cp s3://ha-k8s-etcd-certs/kube-deployments/vote-service.yaml /home/ssm-user/kube-deployments/
      sudo aws s3 cp s3://ha-k8s-etcd-certs/kube-deployments/worker-deployment.yaml /home/ssm-user/kube-deployments/

      sudo kubectl apply -f /home/ssm-user/kube-deployments
    else
      sleep 180
      touch /tmp/timeout
      mkdir -p /etc/kubernetes/pki/etcd
      
      sudo aws s3 cp s3://ha-k8s-etcd-certs/ca.crt /etc/kubernetes/pki/etcd/ca.crt
      sudo aws s3 cp s3://ha-k8s-etcd-certs/ca.key /etc/kubernetes/pki/etcd/ca.key

      sudo aws s3 cp s3://ha-k8s-etcd-certs/master-ca.crt /etc/kubernetes/pki/ca.crt
      sudo aws s3 cp s3://ha-k8s-etcd-certs/master-ca.key /etc/kubernetes/pki/ca.key

      sudo aws s3 cp s3://ha-k8s-etcd-certs/sa.key /etc/kubernetes/pki/sa.key
      sudo aws s3 cp s3://ha-k8s-etcd-certs/sa.pub /etc/kubernetes/pki/sa.pub
      sudo aws s3 cp s3://ha-k8s-etcd-certs/front-proxy-ca.crt /etc/kubernetes/pki/front-proxy-ca.crt
      sudo aws s3 cp s3://ha-k8s-etcd-certs/front-proxy-ca.key /etc/kubernetes/pki/front-proxy-ca.key

      sudo aws s3 cp s3://ha-k8s-etcd-certs/etcd${count.index}.crt /etc/kubernetes/pki/etcd/etcd.crt
      sudo aws s3 cp s3://ha-k8s-etcd-certs/etcd${count.index}.key /etc/kubernetes/pki/etcd/etcd.key

      TOKEN=$(sudo aws s3 cp s3://ha-k8s-etcd-certs/jointoken.txt -)
      TOKEN_HASH=$(sudo aws s3 cp s3://ha-k8s-etcd-certs/jointokenhash.txt -)

      sudo kubeadm join ${aws_lb.ha-k8s-lb[0].dns_name}:6443 --token $TOKEN --discovery-token-ca-cert-hash sha256:$TOKEN_HASH --control-plane --ignore-preflight-errors=all
      # configure kubeconfig for kubectl
      sudo mkdir -p /root/.kube
      sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
      sudo chown $(id -u):$(id -g) /root/.kube/config

      sudo mkdir -p /home/ec2-user/.kube
      sudo cp -i /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
      sudo chown $(id -u):$(id -g) /home/ec2-user/.kube/config

      sudo mkdir -p /home/ssm-user/.kube
      sudo cp -i /etc/kubernetes/admin.conf /home/ssm-user/.kube/config
      sudo chown $(id -u):$(id -g) /home/ssm-user/.kube/config
    fi

  EOF
  count = 3
}

resource "aws_instance" "h8-k8s-master" {

    subnet_id = aws_subnet.ha-k8s-subnets[count.index].id
    ami = "ami-0715c1897453cabd1"
    instance_type = "t2.small"
    key_name = aws_key_pair.kp.key_name
    iam_instance_profile = data.aws_iam_role.ec2iamprofile.id
    associate_public_ip_address = true
    user_data = "${base64encode(data.template_file.user_data_master[count.index].rendered)}"
    tags = {
        "Name" = "h8-k8s-master-${count.index}"
    }
    private_dns_name_options {
        hostname_type = "resource-name"
    }
    private_ip = local.master_private_ip[count.index]
    count = 3
    depends_on = [ aws_instance.h8-k8s-etcd,aws_lb.ha-k8s-lb]
}


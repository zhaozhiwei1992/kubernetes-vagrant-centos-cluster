#!/usr/bin/env bash
# change time zone
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
timedatectl set-timezone Asia/Shanghai
rm /etc/yum.repos.d/CentOS-Base.repo
cp /vagrant/yum/*.* /etc/yum.repos.d/
mv /etc/yum.repos.d/CentOS7-Base-ali.repo /etc/yum.repos.d/CentOS-Base.repo
# using socat to port forward in helm tiller
# install  kmod and ceph-common for rook
yum install -y wget curl conntrack-tools vim net-tools telnet tcpdump bind-utils socat ntp kmod ceph-common dos2unix

# enable ntp to sync time
echo 'sync time'
systemctl start ntpd
systemctl enable ntpd

echo 'disable firewall'
systemctl stop firewalld
systemctl disable firewalld

echo 'disable selinux'
setenforce 0
sed -i 's/=enforcing/=disabled/g' /etc/selinux/config

echo 'enable iptable kernel parameter'
cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
EOF
sysctl -p

echo 'set host name resolution'
hostnamectl set-hostname node$1
cat >> /etc/hosts <<EOF
172.17.8.101 node1
172.17.8.102 node2
172.17.8.103 node3
EOF
cat /etc/hosts

echo 'set nameserver'
echo "nameserver 8.8.8.8">/etc/resolv.conf
cat /etc/resolv.conf

echo 'disable swap'
swapoff -a
yes | cp /etc/fstab /etc/fstab_bak
cat /etc/fstab_bak |grep -v swap > /etc/fstab

#添加网桥过滤及内核转发配置文件
cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# 使配置生效
sysctl -p /etc/sysctl.d/k8s.conf
# 如果本命令无效执行
modprobe br_netfilter
# 然后再次执行
sysctl -p /etc/sysctl.d/k8s.conf

# 安装 ipset 及 ipvsadm
yum -y install ipset ipvsadm

# 配置ipvsadm
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
EOF

# 授权、运行、检查是否加载
chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep -e ip_vs -e nf_conntrack

echo 'docker install'
#create group if not exists
egrep "^docker" /etc/group >& /dev/null
if [ $? -ne 0 ]
then
  groupadd docker
fi

usermod -aG docker vagrant
rm -rf ~/.docker/
yum install -y yum-utils
yum install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors" : [
    "https://reg-mirror.qiniu.com",
    "https://hub-mirror.c.163.com",
    "https://mirror.ccs.tencentyun.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://dockerhub.azk8s.cn",
    "https://registry.docker-cn.com"
  ],
  "exec-opts":["native.cgroupdriver=systemd"],
}
EOF

systemctl enable --now docker

echo 'kubernates install'

# 指定Kubernetes版本
KUBERNETES_VERSION=v1.29.0

yum -y install  kubeadm-1.29.0-150500.1.1  kubelet-1.29.0-150500.1.1 kubectl-1.29.0-150500.1.1
sed -i 's/KUBELET_EXTRA_ARGS=.*/KUBELET_EXTRA_ARGS="--cgroup-driver=systemd"/g' /etc/sysconfig/kubelet
systemctl enable kubelet

# 将第三个节点作为master
if [[ $1 -eq 3 ]]
then

  # 获取镜像列表
  images=$(kubeadm config images list --kubernetes-version=$KUBERNETES_VERSION)

  if [[ $? -ne 0 ]]; then
    echo "Failed to get images list from kubeadm"
    exit 1
  fi

  # 遍历每个镜像，拉取并重新打标签
  for image in $images; do
    # 提取镜像名称和版本
    image_name=$(basename $image)
    if [[ $image == *"coredns"* ]]; then
      aliyun_image="registry.aliyuncs.com/google_containers/coredns:${image_name#*:}"
    else
      aliyun_image="registry.aliyuncs.com/google_containers/${image_name}"
    fi

    # 拉取镜像
    docker pull "$aliyun_image"
    # 打标签
    docker tag "$aliyun_image" "$image"
    # 删除中间镜像
    docker rmi "$aliyun_image"
  done
  echo "configure master and node1"
  kubeadm init --image-repository registry.aliyuncs.com/google_containers --kubernetes-version=$KUBERNETES_VERSION --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$2 --cri-socket unix:///var/run/cri-dockerd.sock
fi

echo "Configure Kubectl to autocomplete"
#source < "(kubectl completion bash)" # setup autocomplete in bash into the current shell, bash-completion package should be installed first.
echo 'eval "$(kubectl completion bash)"' >> ~/.bashrc
source ~/.bashrc


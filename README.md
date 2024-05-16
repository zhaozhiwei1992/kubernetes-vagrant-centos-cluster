# 使用Vagrant和VirtualBox在本地搭建分布式的Kubernetes集群

当我们需要在本地开发时，更希望能够有一个开箱即用又可以方便定制的分布式开发环境，这样才能对Kubernetes本身和应用进行更好的测试。现在我们使用[Vagrant](https://www.vagrantup.com/)和[VirtualBox](https://www.virtualbox.org/wiki/Downloads)来创建一个这样的环境。

使用kubeadm进行初始化

## 准备环境

需要准备以下软件和环境：

- 16g以上内存
- 宿主机: archlinux
- virtualbox 7.x
- vagrant 2.4.1
- k8s虚拟机系统: centos 7.x
- kubernates 1.29.0
- 网络要通畅

## 集群

我们使用Vagrant和Virtualbox安装包含3个节点的kubernetes集群，其中master节点同时作为node节点。

| IP           | 主机名   | 组件                                       |
| ------------ | ----- | ---------------------------------------- |
| 172.17.8.103 | node1 | kube-apiserver、kube-controller-manager、kube-scheduler、etcd、kubelet、docker、flannel、dashboard |
| 172.17.8.102 | node2 | kubelet、docker、flannel、traefik           |
| 172.17.8.101 | node3 | kubelet、docker、flannel                   |

**注意**：以上的IP、主机名和组件都是固定在这些节点的，即使销毁后下次使用vagrant重建依然保持不变。

容器IP范围：172.33.0.0/30

Kubernetes service IP范围：10.254.0.0/16

## 安装的组件

安装完成后的集群包含以下组件：

- kubernetes dashboard
- kubernetes

## 使用说明

将该repo克隆到本地，下载Kubernetes的到项目的根目录。

```bash
git clone https://github.com/zhaozhiwei1992/kubernetes-vagrant-centos-cluster.git
cd kubernetes-vagrant-centos-cluster
```

使用vagrant启动集群。

```bash
vagrant up
```

如果是首次部署，会自动下载`centos/7`的box，这需要花费一些时间，另外每个节点还需要下载安装一系列软件包，整个过程大概需要10几分钟。

如果您在运行`vagrant up`的过程中发现无法下载`centos/7`的box，可以手动下载后将其添加到vagrant中。

**手动添加centos/7 box**

````bash
wget -c http://cloud.centos.org/centos/7/vagrant/x86_64/images/CentOS-7-x86_64-Vagrant-1801_02.VirtualBox.box
vagrant box add CentOS-7-x86_64-Vagrant-1804_02.VirtualBox.box --name centos/7
````

这样下次运行`vagrant up`的时候就会自动读取本地的`centos/7` box而不会再到网上下载。


**在虚拟机内部访问**

如果有任何问题可以登录到虚拟机内部调试：

```bash
vagrant ssh node1
sudo -i
kubectl get nodes
```

**Kubernetes dashboard**

还可以直接通过dashboard UI来访问：https://172.17.8.103:8443

可以在本地执行以下命令获取token的值（需要提前安装kubectl）：

```bash
kubectl -n kube-system describe secret `kubectl -n kube-system get secret|grep admin-token|cut -d " " -f1`|grep "token:"|tr -s " "|cut -d " " -f2
```

**注意**：token的值也可以在`vagrant up`的日志的最后看到。

![Kubernetes dashboard animation](images/dashboard-animation.gif)

只有当你安装了下面的heapster组件后才能看到上图中的监控metrics。

## 管理

除了特别说明，以下命令都在当前的repo目录下操作。

### 挂起

将当前的虚拟机挂起，以便下次恢复。

```bash
vagrant suspend
```

### 恢复

恢复虚拟机的上次状态。

```bash
vagrant resume
```

注意：我们每次挂起虚拟机后再重新启动它们的时候，看到的虚拟机中的时间依然是挂载时候的时间，这样将导致监控查看起来比较麻烦。因此请考虑先停机再重新启动虚拟机。

### 重启

停机后重启启动。

```bash
vagrant halt
vagrant up
# login to node1
vagrant ssh node1
# run the prosivision scripts
/vagrant/hack/k8s-init.sh
exit
# login to node2
vagrant ssh node2
# run the prosivision scripts
/vagrant/hack/k8s-init.sh
exit
# login to node3
vagrant ssh node3
# run the prosivision scripts
/vagrant/hack/k8s-init.sh
sudo -i
cd /vagrant/hack
./deploy-base-services.sh
exit
```

现在你已经拥有一个完整的基础的kubernetes运行环境，在该repo的根目录下执行下面的命令可以获取kubernetes dashboard的admin用户的token。

```bash
hack/get-dashboard-token.sh
```

根据提示登录即可。

### 清理

清理虚拟机。

```bash
vagrant destroy
rm -rf .vagrant
```

### 注意

仅做开发测试使用，不要在生产环境使用该项目。

## 参考

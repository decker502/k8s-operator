## 目标

目前主流的发布系统，大都有隐含的依赖项，部署系统前要安装这些依赖，但国内众所周知的原因，发布系统本身的自动部署逻辑无法直接运行，使部署难度增加，同时还可能使生产环境系统不够纯净，而且操作系统升级时，还需要考虑依赖项的兼容问题。

特性:
- 基于原生操作系统的环境，即可一键发布
- 极其轻量的启动
- 生产环境高可用
- 支持多环境配置
- 尽量少的依赖项，包括发布机和目标机
- 支持主流 Linux 系操作系统
- 发布后自动检查集群健康
- 必要的运维命令(扩容、删除节点、升级)
- 支持私有Registry
- 离线安装

## 依赖

### 发布机

- Linux bash
- Openssl
- SSH
- Rsync

### 目标机

- Linux bash
- SSH
- Systemd

## 操作系统

coreos 1745.5.0 测试通过

强烈推荐在 coreos　安装，省时省力、坑少、Docker原生态

ETCD 3.3.10
kubernetes 1.10.x 1.11.x 1.12.x


## 环境配置

- 发布机到目标机配置 ssh 无密码登录

- env目录下配置环境相应变量，例如开发环境 dev.sh：

    ```bash
    #!/usr/bin/env bash

    export MASTERS=("10.200.0.15 10.200.0.14 10.200.0.13")
    export NODES=("10.200.0.12 10.200.0.11 10.200.0.10")
    ```

    可配置的变量参见　config-default.sh　中的定义

- 准备 二进制文件,置于 binaries目录下
    ```
    kube-apiserver 
    kube-controller-manager 
    kube-scheduler 
    kubelet 
    kube-proxy 
    kubectl
    ```


- 准备必要的Docker镜像(墙后才需要)

    ```
    pause-amd64
    
    calico-node
    calico-cni
    calico-kube-controllers
    
    coredns
    ```

    在配置文件中配置好对应的变量　

    ```
    POD_INFRA_CONTAINER_IMAGE
    COREDNS_IMAGE
    CALICO_NODE_IMAGE
    CALICO_CNI_IMAGE
    CALICO_POLICY_IMAGE
    ```

## 网络组件

默认安装　[Calico](https://www.projectcalico.org/)


## 创建/启动集群

```bash
# env　为变量
bash kube-up.sh ${env}
```

例如：

```bash
bash kube-up.sh dev
```

## 集群扩容

设置变量　SCALE_NODES

```bash

export SCALE_NODES=("10.200.0.11 10.200.0.12")

# env　为变量
bash kube-scale.sh ${env}
```

例如：

```bash
bash kube-scale.sh dev
```

## 删除节点

设置变量　REMOVE_NODES

```bash

export REMOVE_NODES=("10.200.0.11 10.200.0.12")

# env　为变量
bash remove-node.sh ${env}
```

例如：

```bash
bash remove-node dev
```

## 升级Worker节点

确保binaries 中文件为准备升级的版本

设置变量　REMOVE_NODES　和　SCALE_NODES

```bash

export REMOVE_NODES=("10.200.0.11 10.200.0.12")
export SCALE_NODES=("10.200.0.11 10.200.0.12")

# env　为变量
bash remove-node.sh ${env}
bash kube-scale.sh ${env}

```

例如：

```bash
bash remove-node dev
bash kube-scale.sh dev
```

## 销毁集群

### **注意：此操作将清除集群所有数据，仅用于开发测试，请谨慎使用**


```bash
bash kube-down.sh ${env}
```

## 调试模式

```
bash -x kube-up.sh dev
```


## DNS组件

集群安装后，需要安装 [CoreDNS](https://coredns.io/)，以支持 DNS　解析

```bash
# env　为变量
bash deploy-addons.sh ${env}
```


## 参考项目

[kubernetes](https://github.com/kubernetes/kubernetes)

[kubespray](https://github.com/kubernetes-incubator/kubespray)

## License

Code is distributed under MIT license, feel free to use it in your proprietary projects as well.
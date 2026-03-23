# ONTAP S3 对象存储自动化性能测试工具

**联想凌拓科技有限公司**

基于 [MinIO warp](https://github.com/minio/warp) 的 ONTAP S3 对象存储分布式性能测试工具，支持 PUT/GET/MIXED/DELETE/LIST 全场景自动化基准测试，自动生成包含 ECharts 交互图表的 HTML 报告和 Word 报告。

---

## 功能特性

- **自动环境探测**: 自动检测客户端 VM 的 OS、CPU、内存、网络，自动发现 ONTAP 集群版本和 S3 配置
- **自动 S3 配置**: 通过 ONTAP REST API 自动创建 SVM、S3 Server、Bucket、用户和策略
- **分布式 warp 测试**: 多台 VM 同时运行 warp 客户端，真实模拟分布式负载
- **多场景覆盖**: PUT/GET/MIXED(读写混合)/DELETE/LIST 全部操作类型
- **报告自动生成**: HTML 报告(ECharts 交互图表) + Word 报告(.docx)
- **断点续测**: 测试中断后可从上次断点继续，无需重新开始
- **离线运行**: 支持完全离线安装和运行，VM 端零安装(仅需 SSH 访问)
- **S3 验证使用 curl**: 避免引号嵌套问题，无需在 VM 上安装 awscli/boto3

## 系统要求

- **控制节点**: Linux (CentOS 7, RHEL/Rocky 8/9/10, Ubuntu 20.04+), Python 3.6+
- **客户端 VM**: Linux, 控制节点可通过 SSH 访问(密码或密钥认证)
- **ONTAP**: 9.8+, S3 服务已启用, 控制节点可通过 HTTPS 访问 REST API
- **网络**: 控制节点到 VM 的 SSH (22), 控制节点到 ONTAP 的 HTTPS (443), VM 之间的 warp 通信 (7761)

VM 端无需安装任何软件(不依赖 iperf3/sysstat/awscli)，控制节点通过 SSH 自动分发 warp 二进制文件并自动关闭 VM 防火墙。

## 架构

```
                    ONTAP S3 Bench 控制节点
                    (Python 3 + ontap_s3_bench.py)
                           |
              +------------+------------+
              |                         |
         SSH (22)                 HTTPS (443)
              |                         |
    +---------+---------+         ONTAP REST API
    |         |         |         (集群管理LIF)
   VM-1     VM-2     VM-3
  (warp)   (warp)   (warp)
    |         |         |
    +----S3 Protocol----+
              |
        ONTAP S3 Server
         (数据 LIF)
```

## 安装

### 方法一: 离线安装包(推荐)

适用于无法访问互联网的客户测试环境，离线包已包含全部依赖，支持 CentOS 7 / RHEL 8/9/10 / Rocky 8/9。

1. 在有网络的机器上下载离线包 `s3bench.tar.gz` (251MB)
2. 传输到测试环境控制节点
3. 一条命令完成安装:

```bash
tar xzf s3bench.tar.gz && bash s3bench/install.sh
```

如果系统无 tar (minimal 安装):

```bash
python3 -c "import tarfile;tarfile.open('s3bench.tar.gz','r:gz').extractall()" && bash s3bench/install.sh
```

离线包包含:

```
s3bench/
├── install.sh               # 离线安装脚本
├── ontap_s3_bench.py         # 主程序
├── config_example.yaml       # 配置模板
├── bin/warp                  # MinIO warp 二进制 (Linux x86_64)
├── fonts/wqy-microhei.ttc   # 中文字体(报告图表渲染)
└── wheels/                   # Python wheels (支持 3.6/3.8/3.9/3.11/3.12)
```

### 方法二: 在线一键安装

控制节点可联网时使用:

```bash
curl -sSL https://raw.githubusercontent.com/NetApptool/ontap-s3-bench/main/install.sh | bash
```

或使用 wget:

```bash
wget -qO- --no-check-certificate https://raw.githubusercontent.com/NetApptool/ontap-s3-bench/main/install.sh | bash
```

> 安装脚本会自动检测离线资源目录，如果本地已有离线包内容(warp、wheels 等)，将优先使用本地资源，不会下载。

### 方法三: 手动安装

```bash
git clone https://github.com/NetApptool/ontap-s3-bench.git
cd ontap-s3-bench
pip3 install -r requirements.txt
```

## 使用方法

### 交互模式(推荐)

```bash
cd ~/ontap-s3-bench
python3 ontap_s3_bench.py
```

按照交互式引导依次输入 ONTAP 管理 IP、凭据、VM 信息、测试模式等参数。

### 配置文件模式

```bash
python3 ontap_s3_bench.py --config config.yaml
```

### 仅探测(不执行测试)

```bash
python3 ontap_s3_bench.py --dry-run
```

### 仅重新生成报告

```bash
python3 ontap_s3_bench.py --report-only
```

基于工作目录中已有的测试数据重新生成 HTML 和 Word 报告。

## 测试模式

| 模式 | 对象大小 | 并发梯度 | 预估时长 | 适用场景 |
|------|---------|---------|---------|---------|
| quick (快速测试) | 2 种 (64KiB, 1MiB) | 2 级 (8, 16) | ~15 分钟 | 快速验证、演示 |
| standard (标准测试) | 4 种 (4KiB, 64KiB, 1MiB, 4MiB) | 3 级 (4, 16, 32) | ~45 分钟 | 日常测试、POC |
| full (完整测试) | 5 种 (4KiB~4MiB) | 4 级 (4, 8, 16, 32) | ~90 分钟 | 正式基准测试、交付报告 |

## 输出文件

测试完成后在工作目录 (`~/ontap_s3_test`) 下生成:

```
~/ontap_s3_test/
├── reports/
│   ├── {客户名}_ONTAP_S3_性能测试报告.html    # HTML 交互式报告 (ECharts)
│   ├── {客户名}_ONTAP_S3_性能测试报告.docx    # Word 报告
│   └── charts/                                # 图表图片
├── warp_results/                              # warp 原始测试数据
├── env_report.json                            # 环境探测信息
├── checkpoint.json                            # 断点续测进度
└── bench.log                                  # 详细日志
```

## 配置文件示例

```yaml
ontap_mgmt_ip: "192.168.1.100"
ontap_user: "admin"
ontap_password: "password"
svm_name: "svm_s3"
vms:
  - host: "192.168.1.201"
    user: "root"
    password: "password"
  - host: "192.168.1.202"
    user: "root"
    password: "password"
test_mode: "standard"
customer_name: "测试客户"
```

## 断点续测

测试中断后重新运行，工具会检测到上次的进度文件并提示:
- [1] 从断点继续 -- 跳过已完成的场景
- [2] 重新开始 -- 清除进度从头执行

## 注意事项

- warp 的 `--concurrent` 参数是 per-client，实际总并发 = concurrent x VM 数量
- GET 测试从 ONTAP 内存缓存读取，结果代表热数据性能
- ONTAP Select 虚拟化环境性能受限，物理存储性能会大幅高于测试结果
- VM 端不需要安装任何额外软件(iperf3/sysstat/awscli 均已移除依赖)
- S3 连通性验证使用 curl，避免 awscli 引号嵌套问题

## 许可证

MIT License

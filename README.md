# ONTAP S3 对象存储自动化性能测试工具

联想凌拓科技有限公司

一键完成 ONTAP S3 对象存储性能测试全流程：环境探测、S3 配置、分布式压测、报告生成。

## 功能

- 自动检测 VM 和 ONTAP 存储配置
- 自动创建/复用 S3 用户和 bucket
- MinIO warp 分布式多客户端压测 (PUT/GET/MIXED/DELETE/LIST)
- HTML 交互式报告 (ECharts) + Word 品牌报告 + 数据打包
- 断点续跑，测试中断后可从断点继续
- 离线部署，客户端 VM 零依赖安装

## 离线部署（推荐）

适用于无法联网的客户测试环境，离线包已包含全部依赖（warp 二进制、Python wheels、中文字体），无需联网。

```bash
# 1. 下载离线包（204MB）
wget --no-check-certificate -O ontap-s3-bench-offline.tar.gz \
  https://blog.hhok.cc:18443/upload/ontap-s3-bench-offline.tar.gz

# 2. 传输到测试环境控制节点后解压
# 如果系统有 tar：
tar xzf ontap-s3-bench-offline.tar.gz
# 如果系统无 tar（minimal 安装）：
python3 -c "import tarfile; tarfile.open('ontap-s3-bench-offline.tar.gz','r:gz').extractall('.')"

# 3. 执行离线安装
cd ontap-s3-bench-offline
bash install_offline.sh
```

离线包内容：

```
ontap-s3-bench-offline/
├── install_offline.sh        # 离线安装脚本
├── ontap_s3_bench.py         # 主脚本
├── config_example.yaml       # 配置模板
├── bin/warp                  # MinIO warp 二进制
├── fonts/wqy-microhei.ttc   # 中文字体（报告图表用）
└── wheels/                   # Python wheels (支持 3.8/3.9/3.11/3.12)
```

## 在线部署

控制节点可联网时使用：

```bash
curl -skL https://raw.githubusercontent.com/NetApptool/ontap-s3-bench/main/install.sh | bash
```

或使用 wget：

```bash
wget -qO- --no-check-certificate https://raw.githubusercontent.com/NetApptool/ontap-s3-bench/main/install.sh | bash
```

## 手动安装

```bash
git clone https://github.com/NetApptool/ontap-s3-bench.git
cd ontap-s3-bench
pip3 install -r requirements.txt

# 交互模式
python3 ontap_s3_bench.py

# 从配置文件运行
python3 ontap_s3_bench.py --config config.yaml

# 仅探测不测试
python3 ontap_s3_bench.py --dry-run

# 基于已有数据重新生成报告
python3 ontap_s3_bench.py --report-only
```

## 前提条件

- Linux 系统（RHEL/CentOS/Rocky 7-10, Ubuntu 20.04+）
- 控制节点能 SSH 到所有客户端 VM
- 控制节点能通过 HTTPS 访问 ONTAP REST API
- ONTAP 已启用 S3 服务

## 测试模式

| 模式 | 对象大小 | 并发级别 | 预计时间 |
|------|---------|---------|---------|
| 快速 | 64KiB, 1MiB | 8, 16 | ~15 分钟 |
| 标准 | 4KiB, 64KiB, 1MiB, 4MiB | 4, 16, 32 | ~45 分钟 |
| 完整 | 4KiB~4MiB (5种) | 4~32 (4种) | ~90 分钟 |

## 架构

```
控制节点 (运行本工具)
  |
  |-- SSH --> VM1 (warp client)
  |-- SSH --> VM2 (warp client)
  |-- SSH --> VM3 (warp client)
  |          ...
  |-- HTTPS --> ONTAP REST API (集群管理)
  +-- warp master --> 分布式 S3 压测协调
```

## 输出文件

```
~/ontap_s3_test/
├── reports/
│   ├── <客户>_ONTAP_S3_性能测试报告.html    # 交互式报告 (ECharts)
│   ├── <客户>_ONTAP_S3_性能测试报告.docx    # Word 品牌报告
│   └── <客户>_ONTAP_S3_测试数据_*.tar.gz    # 完整数据包
├── warp_results/                              # warp 原始数据
├── env_report.json                            # 环境信息
├── test_matrix.json                           # 测试结果
├── progress.json                              # 断点进度
└── bench.log                                  # 详细日志
```

## 断点续跑

测试中断后重新运行，会提示:
- [1] 从断点继续 -- 跳过已完成的场景
- [2] 重新开始 -- 清除进度从头执行

## 支持的 Linux 发行版

- RHEL / CentOS 7/8/9/10
- Rocky Linux 8/9
- Ubuntu 20.04 / 22.04 / 24.04

自动检测 dnf/yum/apt 包管理器。

## 注意事项

- warp 的 `--concurrent` 参数是 per-client，实际总并发 = concurrent x VM 数量
- GET 测试从 ONTAP 内存缓存读取，结果代表热数据性能
- ONTAP Select 虚拟化环境性能受限，物理存储性能会大幅高于测试结果

# ONTAP S3 对象存储自动化性能测试工具

联想凌拓科技有限公司

## 功能

一键完成 ONTAP S3 对象存储性能测试全流程：

1. **环境探测** — 自动检测 VM 和 ONTAP 存储配置
2. **S3 配置** — 自动创建/复用 S3 用户、bucket
3. **性能测试** — MinIO warp 分布式多客户端压测 (PUT/GET/MIXED/DELETE/LIST)
4. **报告生成** — HTML 交互式报告 + Word 品牌报告 + 数据打包

## 一键部署（推荐）

在任意 Linux 机器上执行一行命令，自动完成所有依赖安装并启动交互式配置：

```bash
curl -skL https://raw.githubusercontent.com/NetApptool/ontap-s3-bench/main/install.sh | bash
```

或使用 wget：

```bash
wget -qO- --no-check-certificate https://raw.githubusercontent.com/NetApptool/ontap-s3-bench/main/install.sh | bash
```

安装脚本自动完成：
- 系统依赖安装（python3、pip3、wget、gcc、openssl-devel 等）
- Python 依赖安装（paramiko、requests、matplotlib、python-docx、numpy 等）
- 项目文件下载
- 中文字体安装（报告图表用）
- MinIO warp 预下载
- 全部验证通过后自动进入交互模式

## 手动安装

```bash
# 克隆仓库
git clone https://github.com/NetApptool/ontap-s3-bench.git
cd ontap-s3-bench

# 安装依赖
pip3 install -r requirements.txt

# 交互模式 (按提示输入)
python3 ontap_s3_bench.py

# 从配置文件运行
python3 ontap_s3_bench.py --config config.yaml

# 仅探测不测试
python3 ontap_s3_bench.py --dry-run

# 基于已有数据重新生成报告
python3 ontap_s3_bench.py --report-only
```

## 前提条件

- Linux 系统（RHEL/CentOS/Rocky/Ubuntu/Debian）
- 控制节点能 SSH 到所有客户端 VM
- 控制节点能通过 HTTPS 访问 ONTAP REST API
- ONTAP 已启用 S3 服务（或有 SVM 可用）
- VM 之间网络互通

## 测试模式

| 模式 | 对象大小 | 并发级别 | 场景数 | 预计时间 |
|------|---------|---------|--------|---------|
| 快速 | 64KiB, 1MiB | 32, 64 | ~10 | ~15 分钟 |
| 标准 | 4KiB, 64KiB, 1MiB, 4MiB | 16, 64, 128 | ~30 | ~45 分钟 |
| 完整 | 4KiB~4MiB (5种) | 16~128 (4种) | ~48 | ~90 分钟 |

## 架构

```
控制节点 (运行本工具)
  │
  ├── SSH ──→ VM1 (warp client + iperf3 + sar)
  ├── SSH ──→ VM2 (warp client + iperf3 + sar)
  ├── SSH ──→ VM3 (warp client + iperf3 + sar)
  │          ...
  ├── HTTPS ──→ ONTAP REST API (集群管理)
  └── warp master ──→ 分布式S3压测协调
```

## 支持的 Linux 发行版

- RHEL / CentOS 7/8/9/10
- Rocky Linux 8/9
- Ubuntu 20.04 / 22.04 / 24.04

自动检测 dnf/yum/apt 包管理器。

## 断点续跑

测试中断后重新运行，会提示:
- [1] 从断点继续 — 跳过已完成的场景
- [2] 重新开始 — 清除进度从头执行

进度保存在 `~/ontap_s3_test/progress.json`。

## 输出文件

```
~/ontap_s3_test/
├── reports/
│   ├── <客户>_ONTAP_S3_性能测试报告.html   # 交互式报告 (ECharts)
│   ├── <客户>_ONTAP_S3_性能测试报告.docx   # Word 品牌报告
│   ├── <客户>_ONTAP_S3_测试数据_*.tar.gz   # 完整数据包
│   └── charts/                              # 性能图表 PNG
├── warp_results/                             # warp 原始数据
├── system_monitor/                           # VM 系统监控
├── env_report.json                           # 环境信息
├── test_matrix.json                          # 测试结果
├── progress.json                             # 断点进度
└── bench.log                                 # 详细日志
```

## 注意事项

- warp 的 `--concurrent` 参数是 per-client，实际总并发 = concurrent × VM 数量
- GET 测试从 ONTAP 内存缓存读取，结果代表热数据性能
- ONTAP Select 虚拟化环境性能受限，物理存储性能会大幅高于测试结果
- 测试完毕后建议清理 warp-bench bucket 释放存储空间

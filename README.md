# Project 3 — CAN Bus ECU Simulator and Logger

![CAN ECU network topology](docs/network_topology.svg)

一个可运行、适合学生作品集的双节点汽车 CAN 项目。两块 ESP32 使用片上 TWAI（兼容经典 CAN 2.0）控制器和外置 3.3 V 收发器组成 500 kbit/s 总线：

- **Engine ECU（节点 A）**：每 100 ms 广播发动机转速、油门、冷却液温度和滚动计数器。
- **Torque + Logger ECU（节点 B）**：验证 CRC-8/SAE-J1850 和滚动计数，计算扭矩限制；连续 3 帧异常或 300 ms 超时即锁定到 60 Nm；同时承载 50 ms 仪表逻辑消息；可选写入 microSD。
- **Host Telemetry ECU（逻辑节点 C）**：Python 按自定义 DBC-style JSON 解码、验证 CRC、保存 CSV、计算总线负载率，并显示时域曲线和 RPM–Torque MAP。

基础版只需两块开发板，不需要 USB-CAN 适配器，也不需要 microSD。主机完成第三节点的记录与可视化职能。若岗位作品集强调独立记录设备，可按后文启用节点 B 的 microSD。

## 目录

```text
config/vehicle.dbc.json       自定义 DBC-style 报文与信号定义
firmware/platformio.ini       两个 ESP32 PlatformIO 构建环境
firmware/src/engine_ecu/      发动机 ECU 固件
firmware/src/torque_logger_ecu/ 扭矩、网关及可选 SD 固件
firmware/src/common/          CAN 驱动与共享协议
host/can_ecu_tool/            Python 解码、记录、仿真、实时绘图
host/tests/                   主机端单元测试
docs/WIRING.md                接线图与上电检查
docs/PROTOCOL.md              报文协议说明
docs/TEST_AND_ACCEPTANCE.md    分阶段测试和验收标准
```

## 推荐硬件（高性价比基础版）

| 数量 | 部件 | 选择理由 | 典型搜索关键词 |
|---:|---|---|---|
| 2 | ESP32 DevKit V1 / ESP32-WROOM-32 开发板 | 自带 CAN 控制器、USB 串口，价格低 | `ESP32 DevKit V1 CP2102` |
| 2 | SN65HVD230 CAN 收发器模块 | 3.3 V 逻辑，直接匹配 ESP32 | `SN65HVD230 CAN transceiver module` |
| 2 | 120 Ω、1/4 W 电阻 | 总线两端终端匹配；模块自带 120 Ω 时不要重复安装 | `120 ohm resistor` |
| 2 | 可传数据的 Micro-USB 线 | 分别烧录和供电 | — |
| 1 | 面包板或接线端子、若干杜邦线 | 搭建短距离总线 | — |

可选：1 个 3.3 V 兼容 microSD SPI 模块和 microSD 卡。不要购买只适合 5 V 逻辑、没有电平转换说明的模块。若 SN65HVD230 模块标有 `120R`/终端跳帽，先确认是否已装终端电阻。

> 重要：ESP32 的片上模块是 CAN 控制器，不是物理层收发器；每块板都必须接一个 SN65HVD230。不要把 ESP32 GPIO 直接接 CANH/CANL，也不要把 5 V 接到收发器的 3V3 引脚。

## 无硬件先运行

需要 Python 3.10+。在项目根目录执行：

```powershell
cd host
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -e .
can-ecu --dbc ..\config\vehicle.dbc.json --simulate --plot --duration 15 --output demo.csv
python -m unittest discover -s tests -v
```

命令会生成 `demo.csv`，显示三条时域曲线和一张实时 RPM–Torque 散点图。若不需要窗口，去掉 `--plot`。

## 烧录两块 ESP32

1. 安装 [Visual Studio Code](https://code.visualstudio.com/) 与 PlatformIO IDE 扩展，打开本项目的 `firmware` 文件夹；或安装 PlatformIO Core。
2. 用第一根 USB 线只连接节点 A，确认串口号。构建并上传 `engine_ecu` 环境。
3. 断开节点 A，用第二根 USB 线连接节点 B，构建并上传 `torque_logger_ecu` 环境。
4. 若上传时一直停在 `Connecting...`，按住开发板 `BOOT`，看到开始写入后松开。
5. 按 [docs/WIRING.md](docs/WIRING.md) 接线。断电接线，万用表检查无短路后再同时上电。

PlatformIO 命令行等价操作：

```powershell
cd firmware
pio run -e engine_ecu
pio run -e engine_ecu -t upload --upload-port COM_A
pio run -e torque_logger_ecu
pio run -e torque_logger_ecu -t upload --upload-port COM_B
```

将 `COM_A`、`COM_B` 换成设备管理器显示的端口。主机工具连接节点 B 的端口：

```powershell
cd host
.venv\Scripts\Activate.ps1
can-ecu --dbc ..\config\vehicle.dbc.json --port COM_B --plot --duration 60 --output road_test.csv
```

注意先关闭 PlatformIO Serial Monitor，否则它会占用同一个串口。节点 B 输出格式为：

```text
@CAN,1234,100,8,204E64015A000051
```

字段依次为网关毫秒时间、十六进制 CAN ID、DLC 和数据。

做失效安全演示时，用另一个 115200 串口终端连接节点 A，分别发送 `BADCRC3`、`BADDLC3` 或 `PAUSE1000`。节点 B 会在连续三帧异常或 300 ms 超时后输出 60 Nm 安全扭矩；完整步骤见测试文档。

## 可选 microSD 独立记录

在 `firmware/platformio.ini` 的 `torque_logger_ecu` 环境中把 `-D ENABLE_SD_LOG=0` 改为 `1`，按 [docs/WIRING.md](docs/WIRING.md) 连接 SPI 引脚后重新烧录节点 B。FAT32 卡根目录会追加 `/canlog.csv`。基础作品不依赖此功能；USB 主机仍会同时记录。

## 你需要亲自完成

- 购买上述硬件，核实收发器供电电压与终端电阻配置。
- 按接线表在断电状态下完成 CANH、CANL、共地、TX/RX 和两端 120 Ω 接线。
- 把两个固件分别烧入两块板，选择正确串口并处理必要的 BOOT 操作。
- 用万用表在**断电**时测 CANH-CANL 约 60 Ω；上电后确认无器件异常发热。
- 运行真实串口采集，完成 60 秒测试，并保存 CSV、终端截图、实时曲线截图。
- 若有示波器/逻辑分析仪：测 CANH/CANL 差分波形和 100 ms 周期；没有也不影响基础验收，可把它列为后续改进。
- 为作品集拍摄总线全景、两端终端电阻特写、烧录/运行画面，并录制 30–60 秒曲线演示视频。

## 已由本项目完成

- 双 ESP32 节点架构和共享 CAN 驱动。
- Engine ECU 驾驶循环、周期广播、滚动计数和 CRC-8/SAE-J1850。
- Torque ECU 的 CRC/DLC/计数器监控、三帧失效策略、300 ms 超时、60 Nm 安全值、三帧恢复策略、USB 网关及可选 SD 记录。
- 0x100、0x101、0x200、0x700 四条报文，50/100/1000 ms 多周期与 ID 优先级竞争。
- 每个信号显式声明 Intel 小端格式，并定义保留位供未来扩展。
- Python 解码、CRC 验证、CSV、最坏情况总线负载估计、时域图、Torque MAP 和硬件仿真。
- 无第三方测试框架依赖的自动化单元测试、接线说明、测试流程、故障排查和量化验收标准。

## 作品集展示建议

展示顺序建议是：系统框图 → 实物接线 → CAN 协议表 → 实时曲线 → CSV 证据 → 故障注入。简历可写：

> Built a two-node 500 kbit/s CAN 2.0A ECU network with CRC-8/SAE-J1850, rolling-counter and timeout failsafe control, multi-rate message arbitration, serial/SD logging, DBC-style decoding, bus-load monitoring, and live torque-map visualization.

本项目仅用于台架学习，不应直接连接真实车辆或安全关键系统。

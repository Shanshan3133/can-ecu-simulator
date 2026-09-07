# 测试步骤与验收标准

## A. 无硬件测试

在 `host` 文件夹创建虚拟环境并安装项目后执行：

```powershell
python -m unittest discover -s tests -v
can-ecu --dbc ..\config\vehicle.dbc.json --simulate --duration 10 --output simulated.csv
```

验收：全部 11 项测试通过；命令退出码为 0；CSV 约有 420 条帧；包含 `ENGINE_STATUS`、`TORQUE_LIMIT`、`DASHBOARD_STATUS` 和两个节点的心跳；业务帧 `crc_ok` 均为 `True`。

自动测试明确覆盖：标准 CRC 检查向量、错误 CRC、错误 DLC、连续三帧异常、滚动计数跳号、300 ms 发送超时、三帧恢复和总线负载计算。

## B. 电气检查（必须断电）

1. 检查每个收发器 VCC 只接 ESP32 3V3。
2. 检查两节点 GND 相连、CANH 对 CANH、CANL 对 CANL。
3. 测 CANH-CANL 电阻。

验收：CANH-CANL 为约 60 Ω（考虑电阻误差，55–65 Ω 可接受）；3V3-GND 不短路。

## C. 单节点启动

分别只连接 USB，打开 115200 串口监视器并按复位。

验收：节点 A 显示 `ENGINE_ECU ready`；节点 B 显示 `TORQUE_LOGGER_ECU ready`。单独运行时 CAN 发送可能因没有 ACK 而失败，这属于正常现象。

## D. 双节点总线测试

1. 关闭串口监视器。
2. 两节点上电，运行：

```powershell
can-ecu --dbc ..\config\vehicle.dbc.json --port COM_B --duration 60 --output hardware_60s.csv
```

3. 查看命令最终统计和 CSV。

验收：

- 60 秒采集至少 2200 行：0x100 与 0x101 各约 600 条，0x200 约 1200 条，另有心跳；启动损失允许。
- 0x100/0x101 平均周期为 90–110 ms；0x200 为 45–55 ms；0x700 为 950–1050 ms。
- CRC 失败数为 0，业务帧保留位均为 0。
- RPM 大致在 950–4100 rpm 变化，油门约 4–64%，扭矩限制随输入变化。
- 0x100 每次有效帧均有相应 0x101；允许启动/停止边界相差 1 条。
- CSV 中稳定态 `bus_load_pct` 的保守估计不超过 1.5%，理论设计值约 1.118%。
- 两节点连续工作 10 分钟不复位、不异常发热。

## E. 实时绘图

```powershell
can-ecu --dbc ..\config\vehicle.dbc.json --port COM_B --plot --duration 60 --output plotted.csv
```

验收：三个时域子图和 RPM–Torque MAP 持续刷新；油门上升时 RPM 与扭矩总体上升；高转速区出现降额趋势；终端实时显示负载率和安全状态；关闭后 CSV 可正常打开。

## F. 建议的故障注入

- 保持主机工具连接节点 B 的串口，同时用另一个 115200 串口终端连接节点 A。
- 向节点 A 发送 `BADDLC3`：接下来的三条 0x100 使用 DLC 7。
- 发送 `BADCRC3`：接下来的三条 0x100 带错误 CRC。
- 发送 `PAUSE1000`：暂停 Engine Status 一秒，制造超时。
- 发送 `NORMAL`：立即清除尚未完成的注入。
- 拔掉一个 120 Ω（断电操作），重新测得约 120 Ω并记录；恢复后再上电。短线可能仍通信，因此只把它作为终端知识演示。
- 暂时交换 CANH/CANL，再上电观察没有有效流量；立即断电并恢复。
- **错误 DLC**：注入 ID 0x100、DLC 7，验证接收端拒绝且不使用其数据。
- **错误 CRC**：翻转 Byte 0 的一位但保留旧 CRC，连续注入三次，验证扭矩锁定 60 Nm 且 reason bit7=1。
- **发送超时**：停止节点 A，验证节点 B 在 300 ms 后进入 failsafe 并继续每 100 ms 发送 60 Nm。
- 恢复节点 A，验证连续三条 CRC 正确且序号连续的帧后退出 failsafe。

上述三个串口命令使总线级负向测试可以在基础两板方案上完成，不需要额外 USB-CAN 设备。

不要在上电时改变面包板接线。完成故障注入后必须恢复正确接线。

## G. 作品集证据清单

- 清晰实物全景，标注 Engine ECU、Torque ECU、CANH/CANL 和两端终端。
- 断电测得约 60 Ω的万用表照片。
- PlatformIO 两个环境构建成功截图。
- 60 秒采集最终统计和 CSV 前几行截图。
- 三条时域曲线、Torque MAP、负载率截图或 30–60 秒屏幕录像。
- 一页协议表和系统框图。
- 可选：示波器差分波形、microSD 中 `canlog.csv`、故障注入前后对比。

## 常见问题

| 现象 | 优先检查 |
|---|---|
| 两边 ready 但无帧 | CANH/CANL、共地、TX/RX 方向、两端供电、500 kbit/s 一致 |
| 只有 Engine 帧、无 Torque | 节点 B 是否收到；DLC/校验是否正确；节点 B 串口是否为所选端口 |
| 串口 Permission denied | 关闭 PlatformIO Monitor、Arduino Serial Monitor 或其他占用程序 |
| ESP32 反复重启 | USB 线/供电、3V3 短路、收发器接错、串口启动日志中的复位原因 |
| 曲线窗口不出现 | 安装带 GUI 支持的 matplotlib，在本地桌面终端运行；先去掉 `--plot` 验证记录 |
| 上传停在 Connecting | 按住 BOOT，写入开始后松开；确认选择正确 COM 端口 |

# 硬件验证复现指南

本文用于复现 10 分钟稳定性、CRC、DLC、滚动计数器和超时故障测试。2026 年 9 月 10 日的实测结果已记录在 [`HARDWARE_RESULTS.md`](HARDWARE_RESULTS.md)。

## 1. 安全与接线

断开两块 ESP32 的 USB 电源后再接线。每个节点按下表连接：

| ESP32 | SN65HVD230 |
|---|---|
| GPIO5 / P5 | TX |
| GPIO4 / P4 | RX |
| GND | GND |
| 3V3 | 3.3V |

总线连接：模块 A `CANH` 接模块 B `CANH`，模块 A `CANL` 接模块 B `CANL`。两个模块的黄色 `120R` 跳帽均保留。禁止带电修改接线。

本次实测使用的端口为：

- `COM3`：Engine ECU（故障命令端）
- `COM5`：Torque Logger ECU（采集端）

如果 Windows 重新分配了端口，请在设备管理器中确认并替换下文命令中的端口号。

## 2. 上传包含 BADCOUNTER3 的新版 Engine ECU 固件

只需向 Engine ECU 上传一次。打开 VS Code 的 PowerShell 终端，运行：

```powershell
cd "C:\Users\massa\Documents\Codex\2026-09-06\referenced-chatgpt-conversation-this-is-an\outputs\can-ecu-simulator\firmware"
```

```powershell
& "C:\Users\massa\.platformio\penv\Scripts\platformio.exe" run -e engine_ecu -t upload --upload-port COM3
```

如果停在 `Connecting...`，按住 Engine ECU 的 `BOOT`，开始写入后松开。看到 `SUCCESS` 才进入下一步。Torque Logger ECU 无需重新上传。

## 3. 10 分钟稳定性测试

关闭全部串口 Monitor，再打开新终端：

```powershell
cd "C:\Users\massa\Documents\Codex\2026-09-06\referenced-chatgpt-conversation-this-is-an\outputs\can-ecu-simulator\host"
```

```powershell
& ".\.venv\Scripts\can-ecu.exe" --dbc "..\config\vehicle.dbc.json" --port COM5 --duration 600 --output "endurance_10min.csv"
```

这次不要加 `--plot`。运行结束后检查：

```powershell
$rows = Import-Csv ".\endurance_10min.csv"
$rows.Count
$rows | Group-Object can_id | Select-Object Name, Count
($rows | Where-Object { $_.crc_ok -eq "False" }).Count
```

合格标准：总帧数约 22,000 或更多；存在 `0x100`、`0x101`、`0x200`、`0x701`、`0x702`；CRC 错误为 0；两块板无重启或异常发热。

## 4. 打开两个故障测试终端

终端 A 用于向 Engine ECU 发送命令：

```powershell
& "C:\Users\massa\.platformio\penv\Scripts\platformio.exe" device monitor --port COM3 --baud 115200
```

先输入 `NORMAL` 并按回车。看到 `FAULT: cleared` 后保持终端 A 打开。

终端 B 用于采集，在 `host` 目录运行：

```powershell
& ".\.venv\Scripts\can-ecu.exe" --dbc "..\config\vehicle.dbc.json" --port COM5 --duration 60 --output "fault_tests.csv"
```

终端 B 开始采集后，在终端 A 每隔约 8 秒依次输入并按回车：

```text
BADCRC3
BADDLC3
BADCOUNTER3
PAUSE1000
NORMAL
```

预期结果：

| 命令 | 预期现象 |
|---|---|
| `BADCRC3` | 3 个 CRC 错误，扭矩进入 60 Nm 安全值 |
| `BADDLC3` | 3 个 DLC=7 的无效帧，扭矩进入 60 Nm 安全值 |
| `BADCOUNTER3` | 计数器跳过 3 个值，检测到序列丢失并进入安全状态 |
| `PAUSE1000` | 0x100 暂停 1 秒，约 300 ms 后进入安全状态 |
| `NORMAL` | 清除待执行故障，连续 3 个有效帧后恢复 |

## 5. 检查故障结果

采集结束后在终端 B 运行：

```powershell
$rows = Import-Csv ".\fault_tests.csv"
"CRC failures: " + ($rows | Where-Object { $_.dlc -eq "8" -and $_.crc_ok -eq "False" }).Count
"DLC-7 frames: " + ($rows | Where-Object { $_.can_id -eq "0x100" -and $_.dlc -eq "7" }).Count
"Failsafe torque frames: " + ($rows | Where-Object { $_.message -eq "TORQUE_LIMIT" -and $_.signals_json -match '"torque_limit":60' }).Count
"Host failsafe rows: " + ($rows | Where-Object { $_.safety_model_failsafe -eq "True" }).Count
```

因为测试故意注入 CRC 错误，采集程序最后返回退出代码 `2` 属于预期行为。

## 6. 出现问题时需要提供的内容

请发送：

1. 当前执行到的章节和命令。
2. 终端从错误开始到最后一行的完整截图。
3. 两块 ESP32 在设备管理器中的 COM 端口。
4. 如果与通信有关，再发送一张能同时看清两块 ESP32、两个 CAN 模块和 CANH/CANL 的接线照片。

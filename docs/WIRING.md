# 接线说明

## 总线拓扑（文字图）

```text
USB 电源/电脑                      USB 电源/电脑（主机工具读此串口）
      │                                      │
 ESP32 A (Engine)                       ESP32 B (Torque/Logger)
 GPIO5 TX ──> CTX   SN65HVD230 A        GPIO5 TX ──> CTX   SN65HVD230 B
 GPIO4 RX <── CRX                         GPIO4 RX <── CRX
 3V3 ───────> 3V3                         3V3 ───────> 3V3
 GND ───────> GND ───────── 共地 ───────── GND <────── GND
               CANH ═════════════════════ CANH
               CANL ═════════════════════ CANL
                │                          │
              120 Ω                      120 Ω
            CANH-CANL                  CANH-CANL
```

CANH 与 CANL 使用一对绞线更好。面包板台架建议总线长度小于 1 m，两个节点位于两端，不要留很长支线。

## 每个 ESP32 到 SN65HVD230

| ESP32 DevKit | SN65HVD230 模块 | 说明 |
|---|---|---|
| 3V3 | 3.3V / VCC | 只用 3.3 V |
| GND | GND | 两节点必须共地 |
| GPIO5 | CTX / TXD / D | 控制器发送到收发器 |
| GPIO4 | CRX / RXD / R | 收发器接收到控制器 |
| — | Rs / S | 若模块引出，正常高速模式通常接 GND；以模块说明为准 |

不同商家丝印可能是 `D/R`、`TX/RX` 或 `CTX/CRX`。若名称不一致，按模块原理图确认方向。

## CAN 总线

| 节点 A | 节点 B |
|---|---|
| CANH | CANH |
| CANL | CANL |
| GND | GND |

在物理总线的两个末端各并联一个 120 Ω 电阻到 CANH 与 CANL 之间。只有两节点短总线时，这就是两个节点附近各一个。部分模块已经焊有 120 Ω：已内置时不要再并联。

断电检查：万用表电阻档量 CANH-CANL，应约为 60 Ω（两个 120 Ω 并联）。约 120 Ω 表示少一个终端；约 40 Ω 表示可能装了三个；接近 0 Ω 表示短路，禁止上电。

## 可选 microSD（只接节点 B）

| ESP32 B | SPI microSD |
|---|---|
| GPIO18 | SCK / CLK |
| GPIO19 | MISO |
| GPIO23 | MOSI |
| GPIO13 | CS |
| 3V3 | VCC（须确认模块支持 3.3 V） |
| GND | GND |

启用 SD 前把卡格式化为 FAT32，并修改构建标志 `ENABLE_SD_LOG=1`。

## 上电顺序

1. 两根 USB 线全部拔掉。
2. 完成接线，检查 3V3-GND、CANH-CANL 无短路。
3. 断电测 CANH-CANL 约 60 Ω。
4. 分别插入两根 USB 线；观察 10 秒，确认收发器和 ESP32 不发热。
5. 只打开节点 B 串口或直接运行 Python 工具。


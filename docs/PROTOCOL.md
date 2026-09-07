# CAN 报文协议与安全策略

总线采用经典 CAN 2.0A、11-bit 标准 ID、500 kbit/s。所有多字节信号均显式使用 **Intel / little-endian**：最低有效字节放在最低地址。选择 Intel 格式是因为 ESP32 和主机均为小端平台，打包、调试和人工读取更直接。当前解码器若遇到未声明字节序或 Motorola 信号会明确拒绝，避免静默误解码。

所有未使用位均定义为 `reserved` 并发送 0，接收端不依赖其值，以便未来增加信号。机器可读的唯一事实来源是 `config/vehicle.dbc.json`。

## 报文优先级与周期

CAN 在同时发送时按 ID 逐位仲裁，数值更小的 ID 优先且不破坏失败节点的帧。

| 优先顺序 | ID | 报文 | 周期 | 发送方 |
|---:|---:|---|---:|---|
| 1 | 0x100 | ENGINE_STATUS | 100 ms | Engine ECU |
| 2 | 0x101 | TORQUE_LIMIT | 约 100 ms/失效时 100 ms | Torque ECU |
| 3 | 0x200 | DASHBOARD_STATUS | 50 ms | 节点 B 内的逻辑 Dashboard ECU |
| 4 | 0x700 | NODE_HEARTBEAT | 1000 ms | 两个物理节点 |

0x100 与 0x200 每 100 ms 会出现周期碰撞，0x100 获得仲裁，0x200 自动等待总线空闲后继续发送。这一设计可用于演示 CAN 的非破坏性优先级仲裁。

## CRC-8/SAE-J1850

0x100、0x101、0x200 的 Byte 7 是对 Byte 0–6 计算的 CRC：

- Polynomial: `0x1D`
- Initial value: `0xFF`
- Final XOR: `0xFF`
- Reflect input/output: false
- 标准检查向量：ASCII `123456789` 得到 `0x4B`

## 0x100 ENGINE_STATUS

节点 A 每 100 ms 发送，DLC 8。

| 字节/位 | 信号 | 换算 | 说明 |
|---|---|---|---|
| Byte 0–1 | engine_rpm | uint16 LE × 0.25 rpm | 0–16000 rpm |
| Byte 2 | throttle_position | uint8 × 0.4% | 0–100% |
| Byte 3 bits 0–3 | rolling_counter | uint4 | 0–15 回绕 |
| Byte 3 bits 4–7 | reserved_counter_upper | — | 固定 0，未来扩展 |
| Byte 4 | coolant_temperature | uint8 − 40 °C | −40–215 °C |
| Byte 5–6 | reserved_future | — | 固定 0，未来扩展 |
| Byte 7 | crc | CRC-8/SAE-J1850 | 覆盖 Byte 0–6 |

## 0x101 TORQUE_LIMIT

节点 B 每收到一条有效 0x100 就响应；失效状态下每 100 ms发送安全值。DLC 8。

| 字节/位 | 信号 | 换算 | 说明 |
|---|---|---|---|
| Byte 0–1 | torque_limit | uint16 LE × 0.1 Nm | 正常算法或安全值 60 Nm |
| Byte 2 | limit_reason | bitfield | bit0 高转速；bit1 高负荷；bit7 失效安全 |
| Byte 3 bits 0–3 | rolling_counter | uint4 | 0–15 回绕 |
| Byte 3 bits 4–7 | reserved_counter_upper | — | 固定 0 |
| Byte 4–6 | reserved_future | — | 固定 0 |
| Byte 7 | crc | CRC-8/SAE-J1850 | 覆盖 Byte 0–6 |

正常扭矩算法：`clamp(80 + throttle×2.2 − max(0, rpm−3500)×0.025, 60, 300)` Nm。

## 0x200 DASHBOARD_STATUS

这是部署在节点 B 上的第三个逻辑 ECU 功能，每 50 ms 广播仪表显示数据，DLC 8。若增加第三块 ESP32，可原样迁移到独立物理节点。

| 字节/位 | 信号 | 换算 | 说明 |
|---|---|---|---|
| Byte 0–1 | display_rpm | uint16 LE × 0.25 rpm | 最近一次有效 RPM |
| Byte 2–3 | display_torque_limit | uint16 LE × 0.1 Nm | 当前限制值 |
| Byte 4 | warning_flags | bitfield | bit0 失效安全告警 |
| Byte 5 bits 0–3 | rolling_counter | uint4 | 0–15 回绕 |
| Byte 5 bits 4–7、Byte 6 | reserved_future | — | 固定 0 |
| Byte 7 | crc | CRC-8/SAE-J1850 | 覆盖 Byte 0–6 |

## 0x700 NODE_HEARTBEAT

两个物理节点每 1000 ms 发送，DLC 4：Byte 0 为 node_id（1=Engine，2=Torque/Logger），Byte 1 为状态，Byte 2–3 为 uint16 LE 运行秒数。

## 失效安全状态机

节点 B 仅把 DLC=8、CRC 正确且序号连续的 0x100 视作完全正常：

1. DLC 错误或 CRC 错误计为一次连续故障，不使用该帧计算扭矩。
2. 滚动计数器跳号时，根据跳过的序号累计丢失帧数。
3. 连续故障/丢失达到 3 帧，或 300 ms 没有有效 Engine Status，进入 failsafe。
4. failsafe 中 Torque Limit 固定为 60.0 Nm，`limit_reason.bit7=1`，每 100 ms 发送。
5. 连续收到 3 条有效且计数连续的 Engine Status 后恢复正常，避免状态来回抖动。

主机端包含同一策略的参考模型并写入 CSV 的 `safety_model_failsafe` 列，用于对 ECU 行为做交叉验证。

## 总线负载预算

主机使用经典 CAN 2.0A 最坏情况位填充估计：8-byte 帧 135 bit，4-byte 帧 95 bit，均含帧间隔。

```text
ENGINE_STATUS:      10 × 135 = 1350 bit/s
TORQUE_LIMIT:       10 × 135 = 1350 bit/s
DASHBOARD_STATUS:   20 × 135 = 2700 bit/s
HEARTBEAT:           2 ×  95 =  190 bit/s
合计                           5590 bit/s
静态最坏情况负载 = 5590 / 500000 = 1.118%
```

设计验收上限设为 **1.5%**。该值是基于观测帧的保守估计，不包含错误重传；真实物理总线负载应使用 CAN 分析仪验证。

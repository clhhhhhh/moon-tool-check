# MoonToolCheck

MoonToolCheck 是一套 MoonBit 库和离线命令行工具。它检查 Agent 工作流中 MCP 工具的参数是否接得上，并用能够独立复核的 JSON 反例解释升级故障。

## 快速开始

需要 MoonBit 和 Node.js。从仓库根目录运行：

```sh
moon test
moon test --target js
moon run cmd/main --target js -- check examples/orders-before.json examples/orders-plan.json
moon run cmd/main --target js -- compare examples/orders-before.json examples/orders-after.json examples/orders-plan.json
moon run cmd/main --target js -- verify examples/orders-after.json examples/orders-plan.json sink examples/orders-witness.json
```

第二条业务命令会输出 `new_failure` 并返回 1。它报告 `sink` 的 `/order_id` 违反类型约束，完整上游响应和下游参数都包含在反例中。

## 输入与输出

工具清单以服务名为键，值可以是 MCP `tools/list` 结果、JSON-RPC 包装的响应，或一组完整的分页响应。工作流以 `steps` 数组描述，每个步骤包含 `id`、`server`、`tool` 和 `args`。参数绑定支持三种形式：

| 形式 | 示例 |
| --- | --- |
| 常量 | `{"literal": 3}` |
| 上游结构化输出 | `{"from": "lookup", "pointer": "/rows/0/id"}` |
| 工作流输入 | `{"input": "/query"}`，其 Schema 在工作流根的 `inputs` 字段声明 |

字段路径支持 JSON Pointer 的对象字段、数组下标和转义。缺失值与 JSON `null` 分开处理。同一上游步骤的多个绑定共享同一份响应。

## 命令

| 命令 | 输入与用途 |
| --- | --- |
| `check CATALOG PLAN` | 检查单条工作流 |
| `compare BEFORE AFTER PLAN` | 检查升级前后的逐步骤变化 |
| `explain-upgrade BEFORE AFTER PLAN` | 附带下游依赖和最短影响距离 |
| `audit CATALOG SUITE` | 批量检查以名称为键的工作流 |
| `compare-suite BEFORE AFTER SUITE` | 批量定位新增故障和证明退化 |
| `catalog-diff BEFORE AFTER` | 按输入逆变、输出协变检查工具清单 |
| `inspect CATALOG`、`inspect-schema SCHEMA` | 定位契约中超出检查范围的关键字 |
| `validate SCHEMA INSTANCE` | 校验 JSON 实例并输出失败路径 |
| `trace CATALOG PLAN TRACE` | 检查已记录的调用顺序、参数和结构化输出 |
| `compare-trace BEFORE AFTER PLAN TRACE` | 用同一份调用记录检查升级差异 |
| `audit-samples CATALOG SAMPLES`、`compare-samples BEFORE AFTER SAMPLES` | 执行已记录的正例与反例 |
| `verify CATALOG PLAN STEP WITNESS` | 重建并复核单个反例 |
| `export-witnesses CATALOG PLAN`、`replay CATALOG PLAN BUNDLE` | 最小化、导出并批量复核反例 |
| `verify-upgrade CATALOG PLAN REPORT` | 批量复核升级报告中的新增失败 |

参数前置 `--strict` 时，涉及契约判定的命令把无法判定的结果视为失败。通常退出码为 0 表示命令成功，1 表示发现失败或策略拒绝，2 表示输入或用法错误。库另外提供 `workflow_sarif` 供 CI 把结果转换为 SARIF。

## 算法与边界

拓扑排序检查有向无环图，包含性证明和有界穷举保留结果的可靠性。反例以完整上游响应重建参数，并在出报告前验证。对于有限定义域，枚举保留同源字段之间的相关性。十进制约束从 JSON 数字词法表示解析，支持大整数、指数表示和精确的 `multipleOf`。部分关键字使用保守判定，超出资源预算或尚未支持的约束输出 `unknown`。

Schema 检查覆盖基础类型、边界、枚举、对象属性与依赖、同构数组与元组、组合和条件约束，以及简单的非递归本地引用。外部或递归引用、正则及动态工作流控制流仍超出当前范围。契约反例表明声明允许的数据足以触发问题，真实服务是否曾产生该值可另用调用记录核对。

[对照实验](examples/REPORT.md)覆盖订单、知识库和报表流程。包含性和反例算法的背景可见 [JSON Subschema Checking](https://andrewhabib.org/publications/issta21-JSONSubschema.pdf) 和 [Witness Generation for JSON Schema](https://www.vldb.org/pvldb/vol15/p4002-sartiani.pdf)。

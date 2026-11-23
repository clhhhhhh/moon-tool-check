# MoonToolCheck 项目申报书

## 基本信息

- 项目名称：MoonToolCheck，基于 MoonBit 的 MCP 工具契约与工作流兼容性检查器
- 参赛者：clhhhhhh
- GitHub 仓库：[clhhhhhh/moon-tool-check](https://github.com/clhhhhhh/moon-tool-check)
- Mooncakes 包：[clbbbb/moon-tool-check@0.1.0](https://mooncakes.io/docs/clbbbb/moon-tool-check)
- 项目方向：MoonBit 基础工具 / Agent 工具链质量保障
- 项目来源：原创实现，参考 MCP、JSON Schema Draft 2020-12 和 JSON Pointer 规范

## 项目简介

MCP 工具升级后，调用方常要等工作流实际执行才发现参数不匹配。MoonToolCheck 读取工具清单和工作流绑定，离线检查上游输出能否满足下游约束。例如，上游将订单编号放宽为可空，而下游仍要求字符串时，检查器会定位到对应步骤和参数，并生成一份可以独立复核的请求。

## 核心功能范围

- 读取 MCP 工具清单和静态有向无环工作流，检查步骤依赖、常量参数、工作流输入和上游输出绑定。
- 对支持的 JSON Schema 约束做校验和包含性分析。有限取值可穷举，来自同一上游响应的多个字段保留取值相关性。
- 比较升级前后的工具契约，报告兼容、不兼容或无法判定。失败时给出上游样本、重建的下游参数和出错路径，支持批量复核反例。
- 提供命令行检查、历史调用记录核对与 CI 严格模式。当前分析范围为静态工作流、已支持的 Schema 关键字及非递归本地引用。

## 实现计划与预期产物

项目以 MoonBit 实现契约解析、兼容性分析、反例生成与复核，交付库 API、JavaScript 后端 CLI、使用文档、回归测试、GitHub Actions 配置及已发布的 Mooncakes 包。可通过 `moon add clbbbb/moon-tool-check` 添加依赖。现有 14 个定向对照用例覆盖订单、知识库、报表及同源字段绑定。工作流检查检出 4 个预设故障，10 个兼容用例均未被标为失败。4 份反例均通过独立 Draft 2020-12 验证器复核。 [实验报告](https://github.com/clhhhhhh/moon-tool-check/blob/main/examples/REPORT.md)

## 参考规范与许可

项目按 Apache-2.0 许可发布。参考 [MCP 工具规范](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)、[JSON Schema Draft 2020-12](https://json-schema.org/draft/2020-12) 和 [RFC 6901](https://www.rfc-editor.org/rfc/rfc6901.html)。

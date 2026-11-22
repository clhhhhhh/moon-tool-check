# 工具链契约对照实验

从仓库根目录运行 `moon build --target js`，安装 Python 的 `jsonschema`，再运行 `python examples/evaluate.py`。原始结果见 [results.json](results.json)。

订单场景将订单编号改为可空，检索场景允许返回空数组，报表场景将计数上限从 100 放宽到 101。每个场景另有描述变更和格式变更两个正常样本。

| 方法 | 故障样本检出 | 正常样本被标记 |
| --- | ---: | ---: |
| 文本差异 | 3/3 | 6/6 |
| 工具 Schema 结构差异 | 3/3 | 0/6 |
| MoonToolCheck 工作流检查 | 3/3 | 0/6 |

MoonToolCheck 为三个故障都生成了包含完整上游响应与下游请求的反例。独立 Python Draft 2020-12 验证器复核通过 3/3。结构差异基线在这组数据上有相同的检出数，MoonToolCheck 另外给出了受影响的步骤和失败数据。

每个用例启动 CLI 五次，统计墙钟时间中位数。计时包含 Node.js 启动和文件 I/O，不能单独代表算法耗时。样本用于验证行为，规模有限。

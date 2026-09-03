# Feedback Trace 工具选择

供反馈调查的 Trace 阶段使用，追踪 Controller → Service → SQL → Adapter/Job 的完整读写链路；仅做只读代码调查，查库仍遵循已选 CDP playbook。

## 判定调查对象

- 按实际涉及的服务仓库 / 模块判断语言，不按编排根目录或仓库名称推断。可先用文件搜索、构建文件与少量源码读取定位目标。
- 目标模块存在业务 `.java` 源码，或构建配置明确声明 Java 模块时，按 Java 项目处理；仅有 `pom.xml` / `build.gradle(.kts)` 不足以断定语言。
- 多语言 / 多服务调查逐个目标选择工具；语言不明时先确认，不默认套用非 Java 回退策略。

## Java：优先 IDEA MCP

1. 发现当前可调用的 IDEA MCP 只读工具，按实际工具 schema 调用，不把“已安装”当作可用。已知工程路径时显式传 `projectPath`；用工程模块 / VCS 根信息及目标文件核对当前 IDEA 工程覆盖所调查的服务或模块，不能使用其他工程的同名符号作为证据。
2. 使用符号搜索定位目标，使用调用层次追踪 callers / callees，再读取源码确认分支、SQL 与外部调用。例如 `search_symbol` → `analyze_calls`（`INCOMING_CALLS` / `OUTGOING_CALLS`）→ `read_file`；具体名称以当前工具发现结果为准。
3. MCP 未连接、工具缺失、目标工程未打开或不匹配、索引未就绪、调用超时 / 报错而无法完成所需查询时，记录实际失败证据并**暂停该目标的 Trace**。单次搜索无结果或空调用树不等同 MCP 无效，应先核对工程、查询范围与符号；证据仍不足时保留待验证项。

不可用时优先提示用户在 IDEA 中打开对应工程，启用 MCP 并等待导入 / 索引完成；同时询问是否允许本次改用 GitNexus。例如：

> 当前无法通过 IDEA MCP 查询 `{service}`（工程：`{project_path}`；原因：`{observed_reason}`）。请在 IDEA 中打开对应工程并确认 MCP / 索引就绪；如果希望本次改用 GitNexus，请明确授权。

- 用户确认工程就绪后，重新核对工程并尝试所需只读查询；仍失败则报告原因并等待，不反复重试。
- **只有用户明确允许本次调查使用 GitNexus 后才能切换**。不得因 GitNexus 已安装、MCP 失败或用户未回复而自动调用 GitNexus，也不得用其他 skill 或直接搜索源码绕过此选择。前述项目识别与可用性核查不受此限制。
- 用户选择等待 / 拒绝切换时保持 `status=investigating`，在调查日志记待处理项；不得将受阻链路当作已验证并据此确认根因。

## GitNexus 与非 Java 项目

- 非 Java 项目保留原策略：优先使用 `gitnexus-debugging` skill（若已安装）。Java 项目仅在获得上述明确授权后进入此路径。
- 按当前工具能力，用接口路径、字段名或症状查询，查看候选符号 callers / callees，结合 process 资源或源码核对完整链路；必要时查询自定义调用链。不要复制 GitNexus 全文手册。
- 非 Java 项目在 GitNexus 不可用时，可用代码搜索与读源码完成 Trace，并注明“未使用 GitNexus”。Java 项目的 GitNexus 回退也不可用时，说明原因并再次请用户选择恢复 IDEA 工程或授权其他调查方式，不能把 GitNexus 授权扩展为任意自动回退。

将结果填入调查报告「相关链路」，在调查日志记录目标服务 / 模块、语言判定依据、实际工具，以及失败原因和用户的回退决定（若有）。工具结果只提供线索；仍需源码、SQL / 日志等证据支持结论。

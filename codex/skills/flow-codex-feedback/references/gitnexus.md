# Trace 步骤与 GitNexus

Trace 阶段追踪完整读写链路。优先使用 **gitnexus-debugging** skill（若已安装）：

1. `gitnexus_query` — 用接口路径、字段名、错误症状搜索
2. `gitnexus_context` — 查看 suspect 符号的 callers/callees
3. 读取 process 资源或源码 — 确认 Controller → Service → SQL → Adapter/Job
4. `gitnexus_cypher` — 自定义调用链（必要时）

将结果填入调查报告「相关链路」章节，不要在本 skill 内复制 gitnexus 全文手册。

GitNexus 不可用时：用代码搜索与读源码完成 Trace，并在调查日志注明「未使用 GitNexus」。

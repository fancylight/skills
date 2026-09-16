---
name: flow-codex-apply
description: 使用 OpenSpec 实现一个已接收的 Flow spec，完成审核、测试和提交；默认单对话自查，授权委派时使用独立审核。在 flow-codex-receive 后使用。
---

# Codex Flow 编码

需求命名、分支与提交遵循 `../flow-codex-core/references/git-conventions.md`；已有需求读取根 change.json；实际写入 Git 仓库前按该规则绑定并校验，提交使用公共脚本，中文描述贯穿业务、文档和测试。

质量要求：读取 ../flow-codex-core/assets/templates/engineering-quality.md 的「实现与审核」。沿用现有结果与授权机制，不增加阶段。

读取 `../flow-codex-core/references/platform.md` 和
`../flow-codex-core/references/checkpoints.md`.

## 实现

单对话模式按 `../flow-codex-core/references/first-delivery.md` 执行：当前执行者完成本 spec 后先自查，再测试、提交和维护根文档；不等待不存在的 REVIEW_REQUEST/REPORT_REQUEST 接收者，不调用要求租约的 report。下方中继流程仅用于已授权委派。跨层风险尽早运行项目小链路，原范围修复只重验受影响部分。

1. 要求明确提供 `change_name` 和 `spec_id`。
2. 编辑前重新检查期望分支和干净基线。
3. 只对当前 spec 执行已安装的 OpenSpec apply 流程。
4. 实现完成后追加进度，并返回 `REVIEW_REQUEST`。

## 审核后恢复

- 收到 `REVIEW_RESULT REJECT` 时，只修复已报告的问题，再次返回 `REVIEW_REQUEST`。
- 收到 `REVIEW_RESULT PASS` 时，执行配置中的测试。失败时修复并重跑，最多三轮。
- 使用公共 Git 规则及根 change.json 的编号，通过公共脚本提交当前 spec 的文件；旧项目格式冲突先同步约定，不能退回旧大写/冒号格式。
- 返回 `REPORT_REQUEST`，等待根 agent 发放报告租约。

apply 阶段不要直接更新根追踪文档。

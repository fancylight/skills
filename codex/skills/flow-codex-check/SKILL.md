---
name: flow-codex-check
description: 只读校验整个 Flow 需求、指定 spec 或修复范围的实际交付。实施收尾自动使用，也可独立检查已有提交；不要求补走派发或汇报，不代替设计 verify 或 apply 中的代码 review。
---

# Flow 交付校验

读取 `../flow-codex-core/references/delivery.md`。保持只读：不写报告文件、不修代码或文档、不提交、不启动环境、不自动重跑测试。

## 确定对象

输入：根路径、change_name、范围（整个需求 / spec / 明确修复），以及每个仓库的已提交修改基线与目标 revision。从 config/task 解析服务、spec、期望分支和根文档。用户已明确的范围优先，不因为某仓有无关脏文件而扩大范围。

基线只能来自用户指定、既定任务记录或本次开始时记录的 Git 状态；不能猜 HEAD~1、默认分支或用完成提交充当起始基线。缺基线时标记 UNVERIFIED，继续能明确执行的检查。按适用任务检查当前未提交内容，包括暂存、未暂存和未跟踪文件；已删除、重命名和二进制文件也须解释用途。

可使用 `scripts/git-scope.py --repo <path> --base <revision> --target <revision>` 获取只读文件清单；省略 base 只盘点工作区并明确 committedScope=UNVERIFIED。它只证明文件范围，不证明业务语义。逐仓运行，审查原始 diff 和必要调用方，不仅看清单。

## 双向检查

按 `../flow-codex-core/references/first-delivery.md` 核对独立预期来源、跨层验证及本次影响范围。项目已接入 local-delivery.json 时，用 scripts/local-delivery.py check 只读核验当前 run；缺失或过期则交实施者执行，check 不自动 run。没有该接线的小修复仍按实际风险检查已有证据，不强制新增测试平台或对话。

- 从原始要求与已确认变更核对根设计、服务 spec、实际实现、验收证据，识别设计遗漏、错误传导和未获确认的范围扩张。
- 从每个实际新增/修改/删除文件反查需求或必要交付用途。临时日志、重复历史副本或新 spec 没有用途依据时报告；不得仅凭后缀判无意义。
- 核对跨服务调用两侧的字段、状态、事务/消息时序和受影响调用方；拿不到其中一侧时记录未验证范围，不以单仓 PASS 代替链路正确。
- 核对根开发文档、概要设计、操作链路、task 和发布内容与当前实现。未受影响文件无需修改；需要更新却未更新时 FAIL。
- 核对实际提交及剩余工作区。相关业务或根文档尚未按任务要求提交时，交付未完成；用户明确不提交时记录该边界。其他任务的脏文件只记录隔离情况。
- 检查已有 review/测试的设计、代码、配置和范围是否仍适用，包括 review 之后的修改。不能仅凭历史 PASS 或任务勾选接受；不相关变化不使全部证据失效。没有独立 review 时不得伪造，可报告静态检查结论及缺口。

## 输出

对已绑定工作目录，按 `../flow-codex-core/references/git-conventions.md` 用公共脚本 audit 检查明确的基线到目标提交，汇总 agent_pass / agent_fail / unclassified / legacy_exceptions。缺绑定或基线只标记 UNVERIFIED，不在本只读入口写元数据或绑定；历史/来源不明的不规范提交仅 WARN，不要求改写历史。

列出需求范围、各仓基线/目标/工作区，随后使用表格：检查项 | PASS / FAIL / UNVERIFIED / NOT_APPLICABLE | 要求位置与实现/证据位置 | 影响 | 补救建议。

FAIL 表示有确证偏差，UNVERIFIED 表示依据或范围不足。任一必要项 FAIL 或 UNVERIFIED 时不得宣称交付完整通过；进行中需求只评价本次指定范围，不因其他未实施 spec 判本次修复失败。静态审核与运行验证分别汇总，声明复用了哪些证据、哪些没有运行。

只在对话输出；实施执行者自行将简短结论写入既定记录。本技能不制造新文件或状态，不要求补造 change/assign/report 历史。

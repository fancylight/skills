# OpenSpec 就绪门禁

每个 Flow spec 对应 **恰好一个 git 仓库** 下的 **一个** OpenSpec change 目录。根 task 里不得一行 c 绑多仓；跨仓须 c 递增（见 `../flow-codex-core/references/platform.md`）。

Flow spec 只有满足以下条件时才可派发：

- 存在 `proposal.md`。
- 存在 `design.md`。
- 存在 `specs/**/*.md`。
- 存在 `tasks.md`。
- `openspec instructions apply --change <spec-id> --json` 不返回 `state: blocked`。

如果 apply 指令被阻断，使用已安装的 OpenSpec continue 流程生成缺失产物。每次继续后重复检查。

不要仅为了通过门禁而创建占位 `tasks.md`。

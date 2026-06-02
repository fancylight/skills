# Task 更新规则

仅对选中的 spec 执行：

1. 将 `[ ]` 改为 `[x]`。
2. 保留简洁的边界和依赖说明行。
3. 追加 `完成：YYYY-MM-DD commit <hash>`。
4. 删除当前 spec 已过期的设计修正标记。
5. 通过替换更新选中服务的标题状态，不要追加历史。
6. 更新根 frontmatter 的 `updated`。
7. 只更新当前 spec 直接满足的 checklist 条目。

对于发版记录：

- 仅在已提交 spec 修改数据库时添加 DDL。
- 仅在部署配置变化时添加配置片段。
- 每个区块标记仓库和 commit hash。

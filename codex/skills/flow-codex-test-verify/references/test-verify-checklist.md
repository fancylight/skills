# 集成测试 Verify 检查清单引用

权威规则位于安装后的同级 `flow-codex-core/assets/templates/test-verify-checklist.md`，其源文件为
`flow/templates/test-verify-checklist.md`。执行本 skill 时读取该共享模板；不要在本文件维护副本。

业务用例优先：design 审核必须从原需求检查 business 的具体输入、配置分支、独立结果推导、关键反例、Y/N和证据边界，再检查技术设计可否真正验证。缺业务用例或只有技术映射为 ERROR。脚本只检查结构与派生一致性，不证明业务覆盖正确；存量设计依 controller 协议重新复核，不继承旧PASS。

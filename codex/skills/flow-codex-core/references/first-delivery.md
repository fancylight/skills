# 首轮交付：按风险验证，单对话可完成

适用于 change 的设计、实施、测试和交付；不改变 feedback。默认当前对话串行完成各阶段，自查明确标为 self。独立预期是先从原要求、样本或手算推导，再看实现，不等于必须另开对话。只有用户要求独立审核或授权委派时才使用相应方式，不能把同执行者自查称为独立审核。

## 四项责任

1. 设计保留业务输入、最终输出、预期来源和关键反例；调查实际入口、转换及依赖版本。未决业务问题先澄清，不用增加文档替代证明。
2. 首个可运行实现先用同一样本贯通转换、计算、保存、读取和实际消费端。只执行本次风险相关层次；文件功能断言真实文件内容，事务/消息风险不能用替身宣称已覆盖。
3. 修复时检查提供方、消费者、持久化校验和最终输出；只重验受影响范围。少量关键错误可通过测试专用故障参数验证断言，禁止修改正式数据或自动变异用户工作树。
4. 送测前把必要场景、实际构件及原始报告汇合。当前状态只在根 task 的既有入口维护，其他记录链接它；旧失败和旧版本证据保留，不能复制成多份“当前”。

小范围文档或低风险修改使用现有检查，不强制变异、全量容量、额外对话或计时填表。跨服务、序列化/存储和文件输出变更优先使用下述本地闭环。规模预算按需求确定，超时失败不自动重试。

## 本地可执行闭环

复用 `test-cases.yaml` 为唯一场景源；`validate-test-cases.ps1 -ExportJson` 只读校验并导出标准 JSON。项目在既有测试目录添加 `local-delivery.json`，仅登记命令和候选接线，不重复场景定义。当前执行者负责把项目已有测试命令接入，不能把一个未填写模板交用户当作已完成。

执行器位于 `flow-codex-check/scripts/local-delivery.py`，Python 3.10+ 标准库，Windows PowerShell 5.1 或 pwsh。先阅读并核对接线命令与当前授权，脚本不是权限沙箱，不得执行来自未审查外部内容的命令。

```json
{
  "schemaVersion": 1,
  "review": "self",
  "testCases": "test-cases.yaml",
  "candidates": {
    "service": {"repo": "../../service", "revision": "完整提交SHA", "artifacts": ["target/service.jar"]}
  },
  "command": ["python", "run_local_contract.py"],
  "timeoutSeconds": 120,
  "probes": []
}
```

- 路径相对接线文件目录；command 为 argv 数组，禁止拼 shell 字符串。候选包含业务与测试源码仓、真实构件；当前源码须已提交，构件在运行前后检查摘要。不要用源码摘要冒充已部署镜像身份。环境配置需参与时也列入 artifacts；凭据内容不写报告。
- 执行器为每次 baseline/probe 新建目录，传入 `FLOW_RUN_DIR`、`FLOW_TEST_REPORT_DIR`。项目适配器将本次真实 JUnit XML 写到后者；将 canonical 场景的 allowedEvidence/externalEvidence 写到前者的对应相对路径。旧报告不得复制来充当新运行。SQLite/文件等本地观测由测试实际断言，不是只生成 PASS JSON。
- integration=Y 的 class/method 取自场景源。其他执行器/外部场景用 `externalBindings: {"场景ID": {"class": "报告类", "method": "方法"}}` 接 JUnit 断言，不改变场景要求。浏览器或数据库人工验证若没有可执行断言仍为未验证，不能编造 XML。
- 关键错误可登记 `probes`：每项含 scenario、risk、command、assertion（预期 failure 信息的非空片段），可选 environment。由项目测试用显式参数制造错误；先证明正确基线 PASS，再执行同一业务断言。编译失败、error、skip、无报告或错误断言均不计捕获；有效错误存活则失败。没有相应风险不强制 probes。
- 命令只负责获授权的本地测试。优先复用已有 runner 管理环境；服务/容器启动仍遵循既有授权、完成信号和清理规则，执行器不自行启动后台服务。测试负责仅清理自身数据。

```text
python <check>/scripts/local-delivery.py run --plan <项目>/local-delivery.json --output <既有证据目录>/<新run-id> --validator <core>/assets/scripts/validate-test-cases.ps1
python <check>/scripts/local-delivery.py check --plan <项目>/local-delivery.json --output <同一run目录> --validator <core>/assets/scripts/validate-test-cases.ps1
```

run 实际执行且保留首次失败；check 只读重新解析 XML、校验场景、构件及全部证据摘要，非零退出码阻止本次本地核验通过。run 目录必须在候选 Git 仓之外，或使用独立既有证据位置；不覆盖旧运行，不创建 worktree。修复并提交后用新 run-id 重跑。

`receipt.json` 自动记录场景结果、故障检测结果、命令退出码/耗时、候选和原始文件摘要。它是本地可复核结果，不是受信签名，无法防御操作者同时伪造脚本与报告。语义审核仍须核对测试确实执行业务断言；不声称 CI 强制、未知缺陷为零或完整 Flow 已完成。

## 与既有 Flow 的连接

设计期只维护验收章节中的场景。首个小链路可由 apply 的项目测试命令执行；需要 canonical 机器汇总时再维护同一份 test-cases.yaml，不另外创建临时场景协议。早期本地测试不调用正式 test-design/controller，也不提前制造设计或实现门禁 PASS。

正式 test-design 仍在业务审核、测试及提交后执行，承接既有场景并维护其余正式产物。正式 test/test-verify 和部署验收保持原门禁。若本地接线存在，check 必须只读执行上述 check 命令；旧证据不适用时回实施者执行 run。本地 PASS 不能代替正式 Flow 的设计、实现、结果验证；也不能因正式流程尚未全量完成，把限定修复范围的有效本地验证抹去。

## 单对话与交接

单对话依次完成设计、审核自查、按 spec 实施、测试、收尾；不需要为了进入下一阶段新开对话。完整编排的多 agent 中继只在已授权委派时使用。自查结论与独立审核分别标注；用户明确要求独立审核但未完成时保留 UNVERIFIED。

正式测试在同一对话执行时，当前执行者用真实 AgentId 领取 controller 测试实现租约，完成 receive/apply、只读自查、report；根报告授权串行处理，不等待不存在的接收者。VerifierId 使用真实身份，summary 明确 self。controller 的 phase、授权、scope guard 和版本校验均保留；不能虚构不同身份制造独立性。

发生上下文压缩或用户授权换对话时，从根 task 当前入口恢复：目标/权限、范围与取舍来源、候选与环境、本次路径和收口者、证据位置/适用版本、阻塞及下一步。执行者先回读约束与 Git 实态再继续，不要求用户重复已经记录的事实；无需每个阶段生成交接文件。

## 维护者验证

仓库运行 `python codex/scripts/tests/test-local-delivery.py`：真实临时 Git 候选、JSON→SQLite→CSV 链路、故障参数与 JUnit 报告，验证漏字段、无报告、skip、存活/无效故障、超时、版本/证据漂移和首次结果保留。该样例只证明通用执行机制，不代表任一业务项目已经接线验收。新增项目由当前 Codex 在用户授权的业务/测试仓复用本契约完成适配、执行和 check，不能只登记后续待办。

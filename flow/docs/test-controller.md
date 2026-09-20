# 集成测试 Controller 协议

集成测试自动化的唯一 machine state 位于编排根
`.flow/changes/<change>/automation-state.yaml`。只用安装后的
`assets/scripts/flow-test-controller.ps1` 读取或写入；manifest、task、agent 口述和 Goal 建议都不能直接改变 phase、授权或 revision。

## 正式切片与恢复入口

Codex 的 v2 需求使用 `assets/scripts/flow-test.ps1 prepare / advance / resume / status`，仍读写本文件所述唯一 state。详细审核输入、选择范围、30分钟总预算和恢复契约见安装后的 `references/test-execution-cycle.md`。新增用户授权开发使用 revise / review-design，不受旧执行预算阻断；developmentNext 与执行 next 分别展示。接纳运行候选仍走 resume，只有明确的新运行授权才能开始新预算轮次并追加 budgetHistory。`execution` 为现有 controller 的附加字段，不是第二套状态机；runs/history 继续保留。

已接入需求的旧写命令返回新入口，旧 `next` 返回新动作。普通失败由当前对话按授权修复并 resume，不能把下列旧 BLOCKED 动作解释为必须重新取得同一授权。新切片必须经过实际 design/implementation/environment 审核，结果仍须语义审核；局部结果不能完成全量。未接入的旧需求继续兼容下述命令。

新执行入口的环境预检失败使用 `TEST_ENVIRONMENT_FAILED`，保存具体失败及构件诊断；下一动作是带修复证据的 `resume`。审核输入完整不等于运行通过。预检通过才进入 `TEST_ENVIRONMENT_VERIFIED`；正式运行后先按选中场景记录 `TEST_EXECUTED_PASS/FAIL`，结果审核才能让对应场景成为当前 PASS。

## 入口规则

每个测试 skill 的第一步都执行 `status` 和 `next`，并核对 canonical state path、当前 phase、authorization ceiling、test/SUT/harness revision 与 configuration fingerprint。state 不存在时，只有 `flow-codex-test-design` 可在产物形成可提交 design revision 后执行一次 `initialize`；其他入口一律 BLOCKED。

| `next` | 唯一允许动作 | Skill |
|---|---|---|
| `STOP_AWAIT_USER_AUTHORIZATION` | 停在当前阶段；收到真实追加授权后调用 grant-authorization | 当前对话 |
| `VERIFY_DESIGN` | 记录结构化 design verifier PASS | `flow-codex-test-verify design` |
| `ISSUE_IMPLEMENTATION_LEASE` | 签发一个 test-implementer lease | `flow-codex-test-assign` |
| `AWAIT_IMPLEMENTATION_RESULT` | 仅持租约 agent receive/apply/report | `flow-codex-test-receive/apply/report` |
| `VERIFY_IMPLEMENTATION` | 记录结构化 implementation verifier PASS | `flow-codex-test-verify implementation` |
| `VERIFY_ENVIRONMENT` | v2 调用只读 `validate-test-environment.ps1`；v1 保留认证 harness 最小探针 | `flow-codex-test` |
| `RUN_ONCE` | 先 `start-run` 原子持久化，再执行 runner；v2 传入 active run fingerprint | `flow-codex-system-test` |
| `AWAIT_RUN_RESULT` | 只接受当前 active run 的结构化结果 | `flow-codex-system-test` |
| `VERIFY_RESULT` | 记录结构化 result verifier PASS | `flow-codex-test-verify result` |
| `COMPLETE` | 完成编排 | `flow-codex-test` |
| `BLOCKED` | 报告阻断并停止 | 所有入口 |

phase 与表中动作不一致时输出 `[FLOW_CONTROLLER] ERROR_TRANSITION` 并停止。`next=BLOCKED` 必须停止；`next=COMPLETE` 才能完成；不得自行选择后续 skill、提升 authorization 或跳过 implementation/environment/result verify。
runner FAIL 在 `record-run` 前完成失败证据收集与完整性检查，记录后进入 `TEST_EXECUTED_FAIL` / `next=BLOCKED`；不得把失败运行送入只接受 PASS 的 result verifier。

若失败被结构化证据明确归类为 `TEST_HARNESS`，且 cleanup 成功，可执行一次受限的 `retry-harness-failure` 修复迁移。该命令要求业务 revision 与配置指纹保持不变、新测试 revision 只修改 `scripts/**` 和 `self-test/**`、新 harness 完成认证，并保留原失败运行；迁移后回到 `TEST_IMPLEMENTED` 重新执行 implementation verify、environment verify 和唯一一次新 revision runner。业务失败、配置失败、未清理现场或同 revision 均不得使用该迁移。

## 初始授权与追加授权

manifest 的 `testAuthorization` 是**初始用户授权**，`stage: design` 不限制 ceiling 只能是 design。用户只授权设计时记 design；已明确授权实现、执行或结果验收时如实记对应上限。controller `initialize` 的 Authorization 必须与已有 manifest 一致。初始化后有效上限唯一读取 `authorization.maxPhase`，初始 manifest 保持不变，避免修改 manifest 导致 v2 配置指纹失效。

初始化高于 design 时，以及所有追加授权，必须提供 `-ReportPath <grant.json>`。内容如下（不是用户批准模板，必须从真实已收到的授权填写，不得自行编造）：

```json
{
  "schemaVersion": 1,
  "grantedBy": "user",
  "requestRef": "真实任务/消息定位",
  "requestText": "用户授权相应测试阶段的原话片段（无凭据）",
  "changeName": "当前change",
  "previousCeiling": "design",
  "ceiling": "execution",
  "testRevision": "当前锁定测试提交",
  "sutRevision": "当前锁定SUT提交",
  "harnessRevision": "当前锁定harness revision",
  "configurationFingerprint": "当前锁定配置指纹"
}
```

初始化报告 `previousCeiling` 为 `none`；追加报告为当前 ceiling。报告保存在既有编排证据目录，不能污染测试仓提交。controller 保存原话、引用、报告 hash 及绑定版本的 grants 审计记录；它校验结构与绑定，**不能认证一段文字真的来自用户**，当前 agent 仍须从实际对话确认授权，不能把报告生成当成授权。

```powershell
& <controller> grant-authorization -StatePath <state> -Authorization execution -ReportPath <grant.json> -TestRevision <locked-test> -SutRevision <locked-sut> -HarnessRevision <locked-harness> -ConfigurationFingerprint <locked-config>
```

只允许严格提升；无报告、非用户来源、缺原话/引用、陈旧绑定、降级/重放均拒绝。提升只更新授权和审计，不改 phase、revision、baseline、配置、租约、verifier、失败或运行证据；运行失败仍须按原失败规则处理。已有明确授权持续有效，不要求每个入口重新询问。`next` 发现下一动作超出上限时返回 `STOP_AWAIT_USER_AUTHORIZATION`，追加后重新读 next，仍不能跳过门禁。

## 存量设计补充与重新审核（实施前）

适用于已有 `TEST_DESIGN_DRAFT` / `TEST_DESIGN_VERIFIED`、尚未签发任何实施租约且没有运行的设计。用户要求复核时，reopen-design 是显式设计入口：next=STOP_AWAIT_USER_AUTHORIZATION 只拦截超出上限的下一阶段，不阻断已授权的设计复核。新业务用例规则不使旧 design PASS 自动变为新规则PASS。默认单对话完成；不新增 phase、不重建 state，不补造历史。

1. 用当前锁定 test/SUT/harness/config 调 `reopen-design -Reason <本次复核原因>`。controller 把旧 revision/verifier 保存到 designRevisions，清除当前 verifier，并回到已有 `TEST_DESIGN_DRAFT`。纯只读诊断无须调用；准备补充/正式重新审核时调用。
2. 由 test-design 在原 `test-cases.yaml` 补充业务内容，先业务预览与审核补齐，再检查技术设计可否验证，更新同一个 test-plan 生成区及 sidecar。继续使用原 `revisions.testBaseline`；配置未变时不重新 resolve。不得改变用户已确认的业务结果以适应旧技术设计。
3. 本迁移仅允许当前 change 的 test-cases.yaml、test-cases.generated.json、test-design.md、test-plan.md；manifest、resolved manifest、夹具、配置、业务与测试代码均保持锁定。它用于补充/复核现有设计；若业务审核发现必须改这些技术契约，明确报告超出本迁移范围，保留待处理状态，不能夹带或清空状态绕过。required 场景不得删除、降为非必需或把原Y改N。
4. 完成静态产物校验并提交后，用旧锁定 `-TestRevision` 和新 `-ProposedTestRevision` 调 `accept-design-revision`，其余锁参数不变。controller 检查真实Git祖先/HEAD、干净工作区、文件范围、必需场景保留和最新静态design门禁；仅推进测试/design/implementation-base revision，稳定 testBaseline 不变，phase仍为DRAFT。
5. 用新测试revision重新运行 `flow-codex-test-verify design`，对原需求和业务预期做真实语义自查。只有当前新报告可记录；旧报告因版本不同拒绝。只获 design 授权时复核后仍等待授权，不执行 JUnit 或 runner。

```powershell
& <controller> reopen-design -StatePath <state> -Reason '业务用例复核' -TestRevision <old-test> -SutRevision <sut> -HarnessRevision <harness> -ConfigurationFingerprint <config>
# 更新允许的设计产物，校验并提交；不要手改state
& <controller> accept-design-revision -StatePath <state> -TestRevision <old-test> -ProposedTestRevision <new-test> -SutRevision <sut> -HarnessRevision <harness> -ConfigurationFingerprint <config>
```

若无需修改产物，reopen 后可在同一revision重新审核；旧记录仍保留。进入实施或执行后的范围变更不使用该入口，不抹去既有租约/运行以伪装成首次设计。

## Lease 与结构化结果

### 实施中已批准的范围修订（运行前）

用户明确修改范围时，原实施者在同一lease内修订canonical源、设计和测试代码，保留旧提交。完成业务范围自查与静态检查后可提交检查点；代码review及report仍须随后完成。使用`record-scope-review`记录新范围的设计自查，不用`reopen-design`回退阶段，不新建state。

该命令仅接受TEST_IMPLEMENTING且从未运行、原持有人有效lease、干净且已提交的测试HEAD；SUT/harness/config与授权上限不变，实际diff限原lease路径。传StatePath、LeaseId、AgentId、VerifierId、ProposedTestRevision及原SutRevision/HarnessRevision/ConfigurationFingerprint和ReportPath。报告必须来自实际用户原话和真实语义审核，格式如下：

```json
{"schemaVersion":1,"result":"PASS","mode":"design-scope","verifierId":"真实身份","grantedBy":"user","requestRef":"实际消息引用","requestText":"用户修改范围的原话","changeName":"change","previousTestRevision":"原designRevision","testRevision":"本次提交","canonicalRevision":"稳定testBaseline","sutRevision":"原SUT","harnessRevision":"原harness","configurationFingerprint":"原配置指纹","previousSourceSha256":"原Git源按LF且末尾一个换行的UTF8摘要","currentSourceSha256":"当前canonical文件摘要","removedScenarioIds":["明确退出的ID"],"diffHash":"implementationBase至本次提交的规范Git diff摘要","summary":"self范围审核：提供方、消费者、保存、最终输出、保留反例及退出边界"}
```

控制器校验真实Git/源/删除集合并写scopeDesignReviews审计；不认证原话真实性或代替语义审核。保留的required/Y不能降级。旧verifier、lease、版本锁、失败、运行历史均不变，不直接进入执行。普通accept-result、implementation/environment/result验证和提交范围检查仍必须通过。实现审核需同时消费原design PASS与本次提交绑定的scope review，不能仅沿用旧设计PASS。

删除检查继续传PreviousTestCasesPath（原Git源按上述LF保存）、PreviousTestRevision、DesignVerifierReportPath（本次scope报告）、ControllerStatePath和TrustedVerifierIdentity；CanonicalRevision始终为稳定baseline。validator必须验证controller审计及源hash匹配，不以人工注释代替。缺口是可修复工程工作，不默认要求用户重新讨论已确认业务；运行后变更、配置/业务版本变化不适用此入口。

- assign 通过 controller 签发 implementation lease；prompt 只传 controller 返回的 `leaseId`、agentId、repository、authorizedPaths、allowed/forbidden capabilities、implementationBaseRevision 和 expiresAt。
- receive/apply/report 每次写入、静态校验或提交前调用 `validate-lease`；无 lease、过期、agent/role/capability/path 不匹配立即停止。
- report 只把结构化 implementation report 和可信 scope guard report 交给 `accept-result`。controller 从 canonical Git 读取 base→proposed diff，成功后才推进 test revision。
- verifier 只提交结构化 PASS；controller 绑定 identity、mode、test/SUT/harness revision、configuration fingerprint 和 summaryHash。
- v2 environment verifier 只消费 `resolved-manifest.json` 和 controller state；它复核输入 hash、provider/SUT/test revision、
  environment file 的引用可用性、managed 启动构件与端口、external preflight probe。它不记录配置值、不启动 managed
  资源，BLOCKED 报告不能提交为 controller PASS。
- runner 只能在 `start-run` 成功后执行一次，再用 `record-run` 记录原始 evidence。agent 口述 PASS 不改变 state。

## Goal

v2 standalone smoke 不写 controller。场景选择的 `fullSuite=false` 证据及 `execution_mode: standalone` 证据不能交给 `record-run` 登记全量 PASS；证据保存在独立 `evidence/runs/<run-id>/`，不覆盖已记录的全量失败。

持续 Goal 只允许：读取 `controller next` → 执行该动作一次 → 将结构化结果交回 controller。用户“尽量完成”不扩大授权。任何命令失败、revision/configuration/capability 漂移或重复 failure fingerprint 都停止，不自动恢复、切换配置、重跑或调用任意后续 skill。

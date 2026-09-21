# 测试交付计时与连续推进

首次测试 design 即执行计时，不依赖 controller 已初始化。使用现有根 change 的 state 路径；脚本只在同目录追加 test-timeline.jsonl，不创建或改变控制状态。

```powershell
& <core>/assets/scripts/flow-test.ps1 timeline -StatePath <root-change>/automation-state.yaml -TimelineAction enter -Stage business -EventId <本次事件唯一ID> -SessionId <本次连续工作会话ID>
```

阶段为 business（业务用例）、technical（技术设计）、review、implementation、preparation、execution、repair、delivery。Agent 在阶段切换时 enter；等待用户或结束当前轮前 pause 并写 Reason；恢复时 resume。跨强退/重启使用新的 SessionId：不把无人工作的间隔算成模型工作。SessionId 不指定时使用任务 ID，无任务 ID 时使用进程 ID；为保证跨重启归类，Agent 应显式提供连续工作会话 ID。相同事件重试复用 EventId，不重复计数。

pause 可提供 Intervention：business、permission-budget、framework、user-change，分别表示业务澄清、权限预算、框架阻塞、用户调整；普通阶段切换不计用户介入。Reason 写具体原因，Reference 引用既有用例、审核或运行，不复制机械字段。交付 finish 必须给 Outcome complete、partial 或 cancelled；计时结束不影响测试判定。仅完成后新增明确需求范围时提供新的 CycleId，自动关联上一周期，普通失败不新开周期。

summary 输出总墙钟耗时（含等待）、阶段耗时及进入次数、暂停、未分类间隔和介入原因。强退缺少结束事件或当前尚未闭合的区间计入未分类；历史没有记录的设计时间不补造。阶段时间不是模型活跃时间，runner 内部耗时属于阶段子集，不能重复相加。计时记录失败只警告，不阻断业务；不能为修台账暂停测试。正式运行摘要合并上述数据。

## 可读用例

业务源仍为 test-cases.yaml，预览首先显示总览表，再展开独立依据、反例与具名明细表。旧八个 business 字符串兼容；复杂用例在 business 下增加 tables，值为单行 JSON 数组，例如：

```yaml
      tables: [{"name":"订单预期","columns":["阶段","扣款次数"],"rows":[["首次请求","1"],["重复请求","1"]]}]
```

表名、列名使用业务语言。规则、输入和逐阶段结果按需要拆表，配置组合展开为具体行，不能用“遍历所有策略”省略预期。每个单元格是文本，行宽与列一致。摘要和详细表必须语义一致，结构检查不产生语义 PASS。

技术设计按初始化、触发、完成判定、断言、清理、成本六项说明实现路径。对异步业务明确每一必要消费者和本次结果关联条件，区分处理完成与存储可见。首次选一个代表性输入走正式入口；更正/重放再选一个双阶段场景。先验证公共链路，再扩展组合；不把几十种参数组合称为最小输入。

## 连续执行与失败处理

静态环境 PASS 只表示允许尝试启动，不表示服务已就绪。正式入口使用实际解释器、配置和启动命令验证必要依赖、服务、消费者与替身契约。准备失败先定位该环节；不重新整批启动碰运气。普通场景一次输入，批量复用服务和连接，按关联结果等待。清理跟踪本次创建资源，覆盖部分成功，不依赖可能未生成的下游索引。

参数、派生文件、已授权配置与依赖错误由 Agent 修复后通过 resume 继续；真正越界只拒绝对应动作。缺少必要用户信息才提问。修复后只重做受影响检查，不重复认证未变化的框架；不修改或放宽业务预期来获得 PASS。旧预算、版本、数据隔离及结果审核仍有效，30分钟预算不因计时、切入口或重启重置。

业务仓无关文件不得删除。无法从启动构件证明其无关时检查真实构建配置，在 manifest.nonBuildInputs 记录精确 repository/path/sha256/reason/evidencePath；审核证据说明为什么未参与构建或运行。该列表绑定执行版本，不接受通配忽略或凭扩展名排除；文件改变后重新判断。参与构建的源代码、配置仍必须与构件一致。

## 实际断言时间

测试适配器在真正执行业务断言前输出一行 `FLOW_TEST_METRIC {"kind":"assertion","scenarioId":"场景ID","at":"UTC ISO8601"}`，runner 从本次 suite 日志收集，并绑定运行和选中场景。只在健康检查、编译或启动时输出此标记无效；审核核对埋点位置。旧测试未埋点时显示未知，不据此拒绝原有有效测试结果。此指标不参与业务 PASS 判定。

运行依赖可在现有 manifest.runner.check 声明 token 数组，使用初始化/测试实际使用的解释器，例如 Python import 或 Node 模块加载检查。runner 在启动资源前执行，继承正式环境引用；失败归入测试运行依赖并保留日志，不逐个启动服务后才发现缺模块。检查只加载必要依赖、不写业务数据；没有新增依赖的旧项目无需补造空检查脚本。该命令纳入原执行指纹及截止时间，不产生新的审核阶段。

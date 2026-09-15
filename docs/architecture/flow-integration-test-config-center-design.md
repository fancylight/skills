# Flow 集成测试环境与本地配置中心设计

> 状态：P1–P4 已实现并通过隔离验证；P5 GLM 结构 shadow PASS、真实配置安全门禁 BLOCKED，runtime pilot 尚未执行。
>
> 本文描述 Flow 的通用测试环境模型。`config-center` 是 GLM 当前采用的一种配置提供者，
> 不是 Flow 必须绑定的基础设施，也不是业务 change 的实现服务。

## 1. 背景与问题定义

当前问题的本质不是“缺少一个 config-center 仓库”，而是 Flow 没有一个稳定、可解析、可锁定的测试环境契约：

- 业务仓中的 `application-dev.yml` 会被本地调试覆盖，不能作为可复现的集成测试配置源；
- system-test 仓、配置提供者、中间件和 SUT 的路径、版本、启动方式分散在文档、命令和 runner 中；
- test-design、静态 validator 与 runner 对 manifest 配置字段的理解不一致；
- managed 依赖尚未启动时，环境检查可能把“预期离线”误判为失败；
- 配置、环境、harness、数据契约与业务断言失败缺少稳定的阶段归因；
- 运行证据尚不能完整证明“SUT 使用了指定配置目标”，也不能保证 cleanup 只停止本轮创建的资源。

已有本地验证证明 Spring Cloud Config native 模式能够提供
`config/{name}/application-{profile}.yml`，且 worker 可以通过启动引导参数加载该配置。
该验证说明 config-center adapter 可行，但不能直接推出所有 Flow 项目都应采用同一种配置中心。

## 2. 目标与非目标

### 2.1 目标

1. 在测试设计前明确判断测试平台、环境描述符和配置提供者是否存在且结构有效；
2. 分别验证外部依赖的执行前联通性，以及 managed 资源启动后的运行时联通性；
3. 让 design verifier、environment verifier、runner 和 result verifier 消费同一份解析结果；
4. 证明配置提供者健康、配置目标可读，并证明 SUT 实际加载了该配置；
5. 对 environment、system-test、SUT、harness、配置目标和执行证据进行 revision/fingerprint 绑定；
6. 在任何失败阶段给出稳定分类、首个失败步骤和原始证据；
7. 不把密码、token、cookie、完整连接串或真实环境文件写入 Flow 产物；
8. 在隔离临时目录和临时 Git 仓中验证全部能力，不依赖真实业务仓和真实秘密。

### 2.2 非目标

- Flow 不内置某个项目的 JDK、驱动、密码、IP 或业务启动命令；
- test-design 不隐式创建其他仓库或修改业务配置；
- config-center 不接收业务 OpenSpec，不参与 `1 spec = 1 executor = 1 commit`；
- design verify 不启动服务，environment preflight 不启动 managed 资源；
- runner 不猜测启动命令、配置名、profile 或 secret 值；
- runner PASS 不替代 result verify、release verify 或 archive 门禁。

## 3. 核心模型

### 3.1 三类对象

| 对象 | 登记位置 | 生命周期职责 |
|---|---|---|
| 业务服务 | 根 `.flow/config.yaml.services` | 接收业务 spec，实现、审核、测试和提交 |
| system-test 仓 | 根 `services` 中 `type: system-test` 的条目 | 接收 `st-api-*` spec，拥有测试代码、harness 和 runner |
| 测试环境资源 | system-test 仓的 environment descriptor | 描述 config provider、中间件、WireMock、生命周期和探针，不接收业务 spec |

config-center 属于第三类对象。它可以指向独立 Git 仓，但不应伪装成普通业务服务。

### 3.2 根配置只保存稳定引用

```yaml
services:
  - name: "glm-system-test"
    path: "glm-system-test"
    type: "system-test"
    description: "Flow 集成测试执行仓"
    flow_initialized: true
    flow_initialized_at: "2026-08-12"

flow:
  protocol_version: "lease-v1"
  test_platform:
    system_test_service: "glm-system-test"
    default_environment: "local"
```

根 config 不重复登记 config-center 路径。system-test service 是测试执行仓的 canonical registry；
环境资源由该仓负责版本化。

### 3.3 Repo 级 environment descriptor

建议路径：

```text
glm-system-test/config/environments/local.json
```

首版使用 JSON，而不是引入新的 YAML parser。现有 `manifest.yaml` 实际也是 JSON-compatible 内容；
是否统一扩展名应另立迁移，不与本设计捆绑。

示例：

```json
{
  "schemaVersion": 1,
  "id": "local",
  "playbook": "docs/local-integration-playbook.md",
  "configurationProvider": {
    "kind": "spring-config-native",
    "repository": "${ORCH_ROOT}/config-center",
    "baseUri": "http://127.0.0.1:8888",
    "configRoot": "config",
    "serviceRef": "config-center"
  },
  "resources": [
    {
      "id": "config-center",
      "kind": "configuration-provider",
      "lifecycle": "managed",
      "executable": "powershell.exe",
      "arguments": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "config/services/config-center/start-native.ps1"],
      "workingDirectory": "${ORCH_ROOT}/config-center",
      "port": 8888,
      "readinessProbe": "config-center-health"
    },
    {
      "id": "mysql",
      "kind": "database",
      "lifecycle": "external",
      "preflightProbe": "mysql-connectivity"
    }
  ],
  "probes": [
    {
      "id": "config-center-health",
      "stage": "runtime",
      "kind": "http",
      "method": "GET",
      "url": "http://127.0.0.1:8888/actuator/health",
      "expectStatus": 200,
      "failureCategory": "CONFIG_INFRA"
    },
    {
      "id": "mysql-connectivity",
      "stage": "preflight",
      "kind": "tcp",
      "hostRef": "MYSQL_HOST",
      "portRef": "MYSQL_PORT",
      "failureCategory": "DATA_SCHEMA_CONTRACT"
    }
  ]
}
```

`lifecycle` 只允许：

- `managed`：runner 本轮负责启动，且只清理由本轮创建的实例；
- `external`：用户或外部平台维护，runner 只读探测，绝不停止；
- `reused` 不作为设计输入，而是 runner 对已存在且身份/健康校验通过的资源记录的运行时状态。

### 3.4 Change manifest

change manifest 只保存本次 change 特有内容，不复制共享环境定义：

```json
{
  "schemaVersion": 2,
  "stage": "design",
  "environment": {
    "id": "local",
    "descriptor": "config/environments/local.json"
  },
  "configuration": {
    "environmentFile": ".env.local",
    "ownership": "human",
    "targets": [
      {
        "application": "worker-service",
        "profile": "dev",
        "relativeFile": "config/worker-service/application-dev.yml",
        "endpoint": "/worker-service/dev",
        "sutEvidence": {
          "kind": "log-pattern",
          "patternId": "spring-config-property-source"
        }
      }
    ]
  },
  "suts": [
    {
      "id": "worker-service",
      "repository": "${ORCH_ROOT}/worker-service",
      "revision": "<git-commit>",
      "lifecycle": "managed",
      "startContract": "config/services/worker-service/start-system-test.ps1",
      "healthProbe": "worker-health"
    }
  ]
}
```

`configuration.environmentFile` 只表示环境变量文件；配置中心由 environment descriptor 的
`configurationProvider` 表示。禁止再用一个 `source` 字段同时表达这两个概念。

### 3.5 Resolved manifest 是唯一执行输入

resolver 将以下输入合并并校验：

```text
root config
  + environment descriptor
  + change manifest
  + locked Git revisions
  + harness certification
  -> resolved-manifest.json
```

resolved manifest 必须：

- 使用绝对 canonical path；
- 展开资源依赖顺序并拒绝环；
- 保存 token array，不保存拼接命令；
- 只保存 secret reference 名称，不保存 secret 值；
- 保存输入文件的 path、revision 和 SHA-256；system-test 当前 revision 由 controller 独立锁定；
- 生成 `configurationFingerprint`；
- 生成并绑定规范化 execution contract hash，防止 resolved manifest 派生字段被单独篡改；
- 在 design verify 后视为不可变执行快照。

design、environment、run、result 四个阶段都读取同一份 resolved manifest。任何输入漂移都必须重新 resolve，
旧 verifier 结论失效，并由 controller 返回 `ERROR_CONFIGURATION_DRIFT` 或 `ERROR_REVISION_DRIFT`。

## 4. 四个问题的闭环

### 4.1 配置中心是否存在

bootstrap/init 负责显式初始化测试平台；test-design 只消费，不隐式创建仓库。

resolver/design verify 依次检查：

1. 根 config 可解析 system-test service；
2. environment descriptor 存在、位于 system-test 仓内且 schema 有效；
3. provider kind 受支持；
4. provider repository canonical path 存在且未越界；
5. `spring-config-native` adapter 所需的 Git 仓、构建文件、启动契约、native 配置和 config root 存在；
6. 每个 target 的 application/profile/path/endpoint 相互一致；
7. target 文件存在，且不含禁止提交的明显秘密或未解析的必需引用。

稳定结果码：

```text
READY
MISSING_TEST_PLATFORM
MISSING_ENVIRONMENT_DESCRIPTOR
UNSUPPORTED_PROVIDER
MISSING_PROVIDER_REPOSITORY
INVALID_PROVIDER_REPOSITORY
MISSING_CONFIG_TARGET
CONFIG_TARGET_MISMATCH
PATH_CONFLICT
```

存在性 PASS 只证明静态结构有效，不证明进程在线。

### 4.2 集成测试联通校验

联通校验分为三个阶段：

| 阶段 | 检查内容 | 是否启动进程 |
|---|---|---|
| design verify | schema、引用、文件、命令、revision、probe stage | 否 |
| environment preflight | 工具、构件、端口冲突、secret reference、external probe | 否 |
| RUN_ONCE runtime readiness | 启动 managed 资源后执行 health、配置目标和 SUT health | 是 |

config-center 链路只有以下三项都有证据才算连通：

1. provider health：例如 `/actuator/health` 返回预期状态；
2. target endpoint：例如 `/worker-service/dev` 返回预期状态且包含目标 property source；
3. SUT consumption：SUT 日志或受控诊断端点证明其加载了该 target。

只检查端口或 provider health 不得声明配置链路 PASS。

### 4.3 集成测试设计

`flow-codex-test-design` 必须产出或引用：

- canonical `test-cases.yaml` 及派生 sidecar；
- environment descriptor 引用；
- configuration target；
- SUT revision、启动契约和健康探针；
- managed/external 边界和资源依赖顺序；
- fixture、seed、cleanup、观测和失败证据；
- resolved manifest 与 fingerprint。

design verifier 必须验证：

- 所有引用可解析且无路径越界；
- provider adapter 与 target schema 匹配；
- probe 为结构化对象，不解析自由文本命令；
- preflight probe 不依赖尚未启动的 managed 资源；
- managed 资源拥有 start/readiness/cleanup 契约；
- external 资源不会出现在 stop plan；
- Windows 启动参数为 token array；
- secret 只以 reference 出现；
- resolved manifest 与输入 hash/revision 一致。

### 4.4 集成测试跑通

RUN_ONCE 的固定顺序：

```text
validate resolved manifest and controller lock
  -> persist start-run
  -> preflight recheck
  -> start managed dependencies in dependency order
  -> runtime readiness probes
  -> verify configuration targets
  -> start SUTs
  -> SUT health and configuration-consumption evidence
  -> seed
  -> execute required suites
  -> collect raw evidence
  -> cleanup resources created by this run
  -> record-run
  -> result verify
```

最终 `INTEGRATION_TEST_RESULT PASS` 必须同时满足：

- 基础环境与配置链路 PASS；
- 所有 SUT 启动和 health PASS；
- required scenarios 全部执行且断言 PASS；
- 原始报告和 evidence index 完整；
- cleanup 成功，或按契约明确记录 retained state 并阻断最终 PASS；
- test/SUT/harness/environment/configuration revision 与 controller 完全一致；
- result verifier PASS。

## 5. 结构化步骤与失败归因

runner 不再依靠异常字符串正则作为主要归因来源。每个步骤输出结构化记录：

```json
{
  "stepId": "start-config-center",
  "phase": "managed-resource-start",
  "resourceId": "config-center",
  "result": "FAIL",
  "category": "CONFIG_INFRA",
  "firstEvidence": "evidence/current/logs/config-center.err.log"
}
```

分类固定为：

| 分类 | 边界 |
|---|---|
| `CONFIG_INFRA` | provider 仓、启动、health、target、配置漂移 |
| `TEST_HARNESS` | runner、认证、工具、脚本、报告收集、WireMock harness |
| `DATA_SCHEMA_CONTRACT` | 数据库/缓存连接、schema、fixture、seed/cleanup 契约 |
| `SUT_BUSINESS` | 环境和 SUT 启动均通过后，required 业务断言失败 |
| `UNDETERMINED` | 缺少原始证据，无法客观归因 |

未知异常默认 `UNDETERMINED`，不能默认归为 `TEST_HARNESS`。若保留历史 `FIXTURE_ASSERTION`，对外统一映射为
`DATA_SCHEMA_CONTRACT`，内部可以保留更细的 reason code。

## 6. Fingerprint 与敏感信息

`configurationFingerprint` 至少绑定：

- environment descriptor path、Git revision 和内容 hash；
- configuration provider repository revision；
- target 的 application/profile/relative path；
- target 文件的脱敏规范化摘要；
- change manifest、resolved manifest 输入、provider、harness 和 SUT revision。

system-test 当前 revision 不进入 configuration fingerprint：resolved manifest 通常与设计产物一起提交，生成前 HEAD
不能代表提交后的 revision。controller 单独锁定 design/test revision；resolved manifest 只记录生成时的
`designInputRevision` 供审计。

禁止进入产物和 evidence：

- secret 值、完整 `.env` 内容；
- 密码、token、cookie；
- 带凭据的完整 JDBC/Redis/Mongo URI；
- HTTP 响应中的敏感 property value。

Flow 只记录 secret reference 名称和“是否提供”，不记录值。低熵 secret 不应直接以普通 SHA-256 持久化；
target 摘要应先移除或替换敏感键，再对 canonical representation 做 hash。

## 7. Controller 与职责边界

保留现有状态链：

```text
TEST_DESIGN_DRAFT
  -> TEST_DESIGN_VERIFIED
  -> TEST_IMPLEMENTING
  -> TEST_IMPLEMENTED
  -> TEST_IMPLEMENTATION_VERIFIED
  -> TEST_ENVIRONMENT_VERIFIED
  -> TEST_EXECUTING
  -> TEST_EXECUTED_PASS
  -> TEST_RESULT_VERIFIED
```

- design verifier 绑定 resolved manifest fingerprint；
- environment verifier 消费结构化 preflight PASS，并绑定同一 fingerprint；
- `start-run` 前重新验证 revision、harness certification 和 fingerprint；
- runner 不修改 controller state，只通过现有命令提交结构化结果；
- 配置或环境失败进入 BLOCKED，不自动修改 `.env.local`、切换 provider 或重跑同一 revision；
- controller 状态机原则上无需新增 phase，只需扩充 verifier/result 契约。

## 8. Skills 与共享实现改动

### 8.1 用户入口

| Skill | 改动 |
|---|---|
| `flow-codex-init` | 显式注册或 scaffold system-test 平台及 environment descriptor；展示计划并确认后写入 |
| `flow-codex-test-design` | 引用已注册环境、声明 target/SUT，生成 resolved manifest；依赖缺失时 BLOCKED |
| `flow-codex-test-verify` | design/implementation/result 均校验 resolved manifest、revision、证据与配置链路 |
| `flow-codex-test` | `VERIFY_ENVIRONMENT` 调用结构化 preflight verifier，PASS 后才进入 RUN_ONCE |
| `flow-codex-system-test` | 按 resolved manifest 启动、探测、运行、归因和 cleanup |

test-assign/receive/apply/report 继续只管理 system-test spec 生命周期，不创建 config-center，不修改业务仓。

### 8.2 共享来源

预计修改：

- `flow/docs/schema.md`、`control-plane.md`、`test-controller.md`；
- `flow/templates/config.yaml.tmpl`、test-design/test-plan/checklist；
- `flow/templates/system-test/config/environments/` 和 runner；
- `flow/scripts/resolve-test-environment.ps1`；
- `flow/scripts/validate-test-environment.ps1`；
- manifest validator、controller 的绑定字段及相关测试；
- Codex skills 的平台触发和编排文字；
- install、validate、distributable-surface 检查。

这些目录是双平台共享协议来源。即使第一阶段只启用 Codex，Claude 侧至少必须同步 schema 消费说明或明确阻断
`schemaVersion: 2`；不得让 Claude 继续写旧 canonical 字段而共享 runner 读取新字段。

## 9. 隔离可行性测试方案

### 9.1 隔离原则

- 每个测试使用系统临时目录和独立临时 Git 仓；
- 不读取或写入真实 GLM 仓、用户 `.env`、真实 config-center 和真实数据库；
- 使用回环地址与操作系统分配的临时端口，不硬编码 8888/7845；
- 使用最小伪 HTTP config provider、伪 SUT 和受控 harness adapter；
- 所有创建的进程记录 PID，测试结束强制检查无泄漏；
- 故障通过 fixture/adapter 注入，不修改正式 harness；
- evidence 只写入临时目录，并执行 secret 扫描。

### 9.2 测试分层

#### A. Schema 与 resolver 单元测试

| 场景 | 预期 |
|---|---|
| 合法 descriptor + manifest | 生成确定性的 resolved manifest |
| descriptor 缺失 | `MISSING_ENVIRONMENT_DESCRIPTOR` |
| provider 仓缺失/非 Git/结构错误 | 对应稳定错误码 |
| target name/profile/path 不一致 | `CONFIG_TARGET_MISMATCH` |
| 相对路径越出允许根 | `PATH_CONFLICT` |
| 资源依赖成环 | 阻断并列出环 |
| managed 缺 start/readiness | schema ERROR |
| external 出现在 cleanup plan | schema ERROR |
| 自由文本 probe 或拼接命令 | schema ERROR |
| secret 值出现在输入或输出 | `ERROR_SECRET_INPUT` |
| 同一输入重复 resolve | byte-stable 输出与相同 fingerprint |

#### B. Environment preflight 隔离测试

使用临时文件、临时 TCP listener 和伪 executable：

| 场景 | 预期 |
|---|---|
| external TCP listener 可用 | PASS |
| external 端口不可用 | `DATA_SCHEMA_CONTRACT` BLOCKED |
| managed 端口空闲 | PASS，不要求服务在线 |
| managed 端口被未知进程占用 | `CONFIG_INFRA` BLOCKED |
| 启动脚本/working directory 缺失 | BLOCKED |
| secret reference 未提供 | BLOCKED，但输出不含值 |
| descriptor 或 target 在 design 后变化 | `ERROR_CONFIGURATION_DRIFT` |

#### C. Runner 生命周期测试

伪 config provider 提供 `/actuator/health` 与 `/{name}/{profile}`；伪 SUT 提供 health 并输出受控的配置加载记录。

| 场景 | 预期 |
|---|---|
| provider → target → SUT consumption → suite | PASS，三段证据齐全 |
| provider 启动失败 | `CONFIG_INFRA` |
| provider health 失败 | `CONFIG_INFRA` |
| target 404/name-profile 不匹配 | `CONFIG_INFRA` |
| provider 健康但 SUT 未加载 target | `CONFIG_INFRA`，不得执行 suite |
| SUT 启动或 health 失败 | 非 `SUT_BUSINESS` |
| seed/schema 失败 | `DATA_SCHEMA_CONTRACT` |
| suite 业务断言失败 | `SUT_BUSINESS`，前置阶段必须已 PASS |
| 原始证据缺失 | `UNDETERMINED` |
| cleanup 失败 | 最终不得 PASS，并记录 retained state |
| 复用测试前已存在的健康进程 | 标记 `reused`，cleanup 不停止它 |
| runner 本轮创建进程 | cleanup 只停止这些 PID |

#### D. Controller 集成测试

在临时 Git 仓中验证：

- design/environment/run/result 使用相同 fingerprint 时状态正常推进；
- descriptor、target、SUT 或 harness 任一漂移都会拒绝推进；
- environment 未验证不能 `start-run`；
- 同一 revision 失败后不能重跑；
- runner PASS 不能跳过 result verifier；
- ceiling 不足时停止等待用户授权。

#### E. 兼容与迁移测试

- 旧顶层 `configurationSource/requiredEndpoints/connectivityProbe/ownership` 可在限定迁移期读取；
- resolver 输出迁移警告，但只写 `schemaVersion: 2`；
- 同时出现新旧字段时拒绝，避免歧义；
- 当前 runner/harness certification 的已有 self-test 全部继续通过；
- Claude 旧入口遇到 v2 时明确阻断，或同步生成 v2，不能静默产生错误 manifest。

#### F. 安全与故障注入

- 在 env、target、HTTP 响应和日志中注入假 token/password/JDBC URI；
- 验证 resolved manifest、controller state、summary、failure report 和 evidence index 均不泄漏；
- 模拟中断、超时、子进程退出、报告缺失、cleanup 部分失败；
- 测试完成后断言无残留进程、无占用端口、无工作区外写入。

### 9.3 隔离验证批次

| 批次 | 内容 | 是否改生产实现 |
|---|---|---|
| P0 | 固化当前 validate/controller/harness 基线 | 否 |
| P1 | 仅实现 schema + resolver prototype 和 A 类测试 | 已实现并隔离 PASS |
| P2 | 实现 preflight verifier 和 B/D 类测试 | 已实现并隔离 PASS |
| P3 | 实现伪 provider/SUT adapter，验证完整生命周期 C/F | 已实现并隔离 PASS；未切换 v1 默认 runner |
| P4 | 旧 manifest 迁移与全量回归 E | 已实现并隔离 PASS；v1 原链路保持回归兼容 |
| P5 | worker-service shadow 验证，只读真实配置结构，不写真实仓 | 结构 PASS；原始配置因明文敏感项 BLOCKED；runtime 待授权与配置整改 |

P1–P4 全部 PASS 后，才能申请真实 `worker-service` pilot。隔离 PASS 证明 Flow 编排与 runner 机制可行，
不证明真实密码、数据库权限和业务配置正确。

### 9.4 验收证据

每个批次至少保存：

- 测试命令、exit code 和原始报告；
- 临时仓 revision 与输入 fingerprint；
- 每个场景的结构化 step result；
- 进程/端口 cleanup 结果；
- secret scan 结果；
- 现有回归测试结果。

只有原始证据存在且 revision 可追溯时才能声明该批次 PASS。

## 10. 对当前整体的影响

### 10.1 直接影响面

| 区域 | 影响 | 风险 |
|---|---|---|
| manifest schema | 顶层旧配置字段迁移为 environment + configuration | 高 |
| artifact validator | 改为校验 resolved manifest 和结构化 probe | 高 |
| system-test runner | 生命周期、probe、归因、cleanup 所有权增强 | 高 |
| controller | 复用现有 phase，扩充 fingerprint/verifier result | 中 |
| init/test-design/test/test-verify skills | 改入口职责和产物约束 | 中 |
| install/validate | 安装新 descriptor 模板和共享脚本 | 中 |
| Claude 兼容 | 共享 schema 必须同步消费或显式阻断 | 高 |
| 业务服务仓 | 首期不改；pilot 才增加启动脚本/证据契约 | 低到中 |

### 10.2 不应受影响的区域

- 业务 Flow 的 design/assign/receive/apply/review/report 主链；
- `1 spec = 1 executor = 1 commit` 和串行 report 租约；
- canonical test-cases 与实现审核生命周期；
- unit test、release verify、archive 的既有职责；
- 不使用 system-test 的存量 legacy change。

### 10.3 回归门禁

每阶段实现后至少运行：

```powershell
.\codex\validate.ps1
.\flow\scripts\tests\test-validate-test-artifacts.ps1
.\flow\scripts\tests\test-validate-test-cases.ps1
.\flow\scripts\tests\test-flow-test-controller.ps1
```

另需在隔离临时 harness 副本中运行 certification self-test，并运行 install/distributable-surface 检查。
任何既有 controller、harness、scope guard 或 canonical test-case 回归失败都不得继续 pilot。

## 11. 实施顺序与门禁

1. 冻结 v2 schema、descriptor 和 resolved manifest 示例；
2. 实现纯 resolver 与隔离单元测试，不改 runner；
3. 实现 environment preflight 和 controller 绑定；
4. 增强 runner 的结构化步骤、资源所有权和配置三段式证据；
5. 实现旧字段单向迁移，更新共享文档、模板和宿主入口；
6. 全量隔离故障注入与既有回归；
7. 用 worker-service 做 shadow pilot；
8. pilot PASS 后再决定是否默认启用及迁移其他服务。

每一步必须是独立可审核、可回退的提交。不得在一次变更中同时引入 schema、真实 config-center、真实秘密和业务服务迁移。

## 12. 最终验收标准

- 缺失或无效的测试平台、descriptor、provider repo、target 均能在启动前得到稳定错误码；
- managed provider 离线不会在 preflight 被误判，external 依赖不可用会明确阻断；
- config provider health、target endpoint、SUT consumption 三段证据完整；
- 所有阶段消费同一 resolved manifest 和 configuration fingerprint；
- Windows 启动命令始终以 token array 或受控脚本执行；
- runner 只清理本轮创建的资源，不停止 external 或 reused 资源；
- 失败归因来自结构化步骤，证据不足时为 `UNDETERMINED`；
- evidence 和 controller state 不包含敏感值；
- 隔离测试覆盖成功路径、全部主要故障和进程清理；
- 现有 Codex validate、controller、harness、artifact/case guard 回归全部 PASS；
- worker-service shadow pilot 通过后，才允许声明真实环境可行并逐服务迁移。

# Flow 本地配置中心与集成测试方案

状态：目的说明与可行性验证方案（暂不修改 Flow skill 实现）  
验证对象：`worker-service`  事件：2026-08-05

## 1. 结论

把 Flow 子服务的本地启动配置集中放到
`C:\Users\chenk-u\code\glm\config-center\config`，由本地启动的 Config Server
以 native 模式提供，集成测试启动服务时显式指定配置中心、配置名和 profile，这个方案可行。

本次已经完成最小链路验证：

1. 将 `worker-service` 当前可用的 `application-dev.yml` 放到
   `config-center/config/worker-service/application-dev.yml`。
2. 以 native 模式启动 config-center，监听 `8888`。
3. 请求 `http://127.0.0.1:8888/worker-service/dev` 成功返回配置。
4. 使用当前 `worker-service` 源码和临时修改后的 MySQL 8.0.33 POM 执行
   `mvn package -DskipTests`，构建成功。
5. 启动新 jar 时，worker 日志明确记录从
   `file:C:/Users/chenk-u/code/glm/config-center/config/worker-service/application-dev.yml`
   加载配置，并在 `7845` 提供健康检查，返回 `200`。

因此，配置中心取配置失败和服务自身依赖、驱动、端口、外部中间件等启动失败，应当在 Flow 中被识别为两类不同问题。

## 2. 要解决的问题

### 2.1 常见启动问题文档

不同仓库的 `dev` 文件可能被覆盖或被临时修改，Agent 在集成测试前遇到驱动、JDK、依赖服务、端口等问题时容易反复尝试。

这部分不放进 skill 实现，建议在 Flow 仓库中单独维护一个本地启动文档目录，记录：

- 常用编译和启动命令；
- 已知的 JDK、Maven、数据库驱动和依赖版本要求；
- 外部依赖的本地替代方案；
- 常见错误与对应的检查命令。

skill 只负责找到并提示文档，不把每个仓库的业务启动细节硬编码到通用流程中。

### 2.2 配置文件被覆盖

服务仓库中的 `src/main/resources/application-dev.yml` 既是代码的一部分，又经常被不同开发者用于本地调试。它不适合作为集成测试的唯一配置事实来源。

建议把本地集成测试配置迁移到 config-center 仓库，服务仓库中的 `dev` 文件只保留兼容启动所需内容，或者在后续确认迁移完成后不再作为集成测试配置源。

## 3. 目标目录结构

```text
C:\Users\chenk-u\code\glm\config-center\
└─ config\
   ├─ worker-service\
   │  └─ application-dev.yml
   ├─ worker-register-service\
   │  └─ application-dev.yml
   └─ <其他 Flow 子服务>\
      └─ application-dev.yml
```

目录名是 Config Client 使用的 `spring.cloud.config.name`，文件名中的 `dev` 是 profile。也就是说：

```text
spring.cloud.config.name=worker-service
spring.cloud.config.profile=dev
```

会由 config-center native backend 在 `config/{application}` 下寻找
`application-dev.yml`。

## 4. 两类配置要分开

这是本方案最关键的边界。

### 4.1 config-center 自己的配置

config-center 必须知道：

- 使用 `native` profile，而不是默认的 Git backend；
- 本地配置目录在哪里；
- 监听哪个端口；
- 本地是否关闭 Eureka 等外部发现依赖。

第一次验证可以通过启动参数提供这些值，不需要修改 config-center 的源码配置：

```powershell
cd C:\Users\chenk-u\code\glm\config-center

mvn.cmd spring-boot:run `
  '-Dspring-boot.run.profiles=native' `
  '-Dspring-boot.run.arguments=--server.port=8888,--spring.cloud.config.server.native.search-locations=file:C:/Users/chenk-u/code/glm/config-center/config/{application},--eureka.client.enabled=false'
```

其中 `{application}` 必须保留，它是 Config Server 用来替换配置名的占位符。

检查命令：

```powershell
curl.exe http://127.0.0.1:8888/actuator/health
curl.exe http://127.0.0.1:8888/worker-service/dev
```

### 4.2 worker-service 的启动引导配置

worker 在拉取远程配置之前，必须先知道配置中心地址和要拉取的配置名。因此下面这些参数不能依赖远程 `application-dev.yml` 提供：

- `spring.cloud.config.uri`；
- `spring.cloud.config.name`；
- `spring.cloud.config.profile`；
- `spring.cloud.config.fail-fast`；
- 是否通过 Eureka 发现 Config Server。

第一次验证可以直接放在 worker 的启动参数中：

```powershell
cd C:\Users\chenk-u\code\glm\worker-service

mvn.cmd package '-DskipTests'

java `
  '-Dspring.cloud.config.uri=http://127.0.0.1:8888' `
  '-Dspring.cloud.config.name=worker-service' `
  '-Dspring.cloud.config.profile=dev' `
  '-Dspring.cloud.config.fail-fast=true' `
  '-Dspring.cloud.config.discovery.enabled=false' `
  '-Deureka.client.enabled=false' `
  -jar target\worker-service-3.4.1-SNAPSHOT.jar `
  --spring.profiles.active=dev
```

这里的 `spring.cloud.config.name=worker-service` 负责选择配置目录；它和远程文件中的 `spring.application.name` 不是同一个概念。当前 worker 的远程 dev 配置仍可保留原有应用名，不需要为了本次验证强行重命名。

后续稳定实现可以把这些参数放到 Flow 的 system-test manifest 或本地启动脚本中。它们属于“如何连接配置中心”的启动引导，不属于业务 `application-dev.yml`。

### 4.3 `application-dev.yml` 不应该再写配置中心地址

从 worker 仓库复制到 config-center 的 `application-dev.yml` 不需要增加 config-center 地址。这样做会形成启动前无法解析的自引用：worker 必须先拿到地址，才能取得这份文件。

正确关系是：

```text
worker 启动参数/manifest
        │  uri + name + profile
        ▼
本地 config-center（native）
        │  读取 config/{name}/application-{profile}.yml
        ▼
worker 应用配置
```

## 5. Flow skill 后续如何接入

本次只记录方案，不修改 skill。后续可以把 config-center 作为集成测试的可选或必选前置检查项：

1. 检查 config-center 进程或健康地址是否可用；
2. 用明确的 `name/profile` 请求配置端点，确认 HTTP 成功；
3. 检查本地 `config/{name}/application-{profile}.yml` 是否存在；
4. 对配置做非敏感校验，例如文件指纹、必需键、未解析占位符；
5. 通过检查后再启动子服务；
6. 在失败报告中区分“配置中心不可用”“配置不存在”“配置内容不完整”和“服务自身启动失败”；
7. 在证据中记录配置名、profile、配置文件指纹和来源路径，不输出密码、token 等敏感值。

建议 Flow manifest 未来增加类似下面的声明，而不是让 skill 猜服务名：

```yaml
config:
  provider: local-config-center
  uri: http://127.0.0.1:8888
  name: worker-service
  profile: dev
  required: true
```

## 6. 分阶段落地

### 阶段一：当前验证

- 建立 `config-center/config` 目录约定；
- 迁移一个服务的 dev 配置；
- 用 native config-center 启动并验证 Config Client 拉取；
- 不改 Flow skill。

### 阶段二：项目侧文档和配置安全

- 在 Flow 仓库新增常见启动文档目录；
- 为 config-center 增加本地配置模板和忽略规则；
- 明确哪些值可以进入仓库，哪些值必须通过本地环境变量或秘密管理提供。

### 阶段三：Flow skill 前置检查

- 在 system-test 启动服务前执行 config-center preflight；
- 统一记录启动参数和配置来源；
- 将常见启动文档作为失败时的定向提示。

### 阶段四：逐个迁移其他子服务

- 每个服务单独确认 `config.name`、profile、端口和外部依赖；
- 再将对应配置加入同一 config-center 目录；
- 不因为一个服务的配置结构而假设所有服务一致。

## 7. 当前验证记录与注意事项

- config-center native 健康检查：通过；
- `worker-service/dev` 配置端点：通过；
- `worker-service` 当前 POM 使用 MySQL 8.0.33，`mvn package -DskipTests`：通过；
- worker 日志记录的配置来源：`config-center/config/worker-service/application-dev.yml`；
- worker `7845/actuator/health`：返回 `200` 和 `status=UP`。

当前复制到 config-center 的 dev 文件含有本地连接信息和敏感配置。它目前只作为本地验证文件，尚未提交。正式落地前必须确定 `config/` 的 Git 策略：可以将真实本地配置加入忽略并提供脱敏模板，也可以接入专门的本地秘密管理机制，不能把真实密码、token 或生产连接信息直接提交到仓库。


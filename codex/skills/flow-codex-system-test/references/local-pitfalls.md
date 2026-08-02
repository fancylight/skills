# 本地集成常见卡点

执行前读取 config 解析出的 system-test 仓内 `docs/local-integration-playbook.md`。

## 强制 preflight（手工 IDEA 模式）

1. `doctor -Change <change>` 通过。
2. 端口与 manifest 一致（如 7846/7845/7847/9676/18080）；**同一端口只有一个进程**。
3. 发版 SQL：根 `release-sql/` 或 `fixtures/release/` 已按序执行；SQL 变更后重跑对应脚本。
4. S4 前：agg 已加载 `application-system-test.yml` + `-Dregister-feign-var=register-service`。
5. S4 前：Redis db=8 可由 `GjgSessionSupport` 写入；agg `jwt.secret` 对齐。

## 失败归因顺序

1. 服务 health → 2. SQL/sequence/夹具 → 3. Feign/WireMock → 4. 鉴权 → 5. 业务断言。

## 代码变更后

- register 新 commit：重启 register，跑 manifest 全量 `apiTestFilter` 冒烟。
- 仅发版 SQL（如 flow17）：重跑对应 release-sql，再冒烟；未覆盖路径须补用例或明示 gap。

## 禁止

- 未确认服务 down 就改业务代码。
- runner 与 IDEA 同时占 aggregator 端口。
- 把 `seed-fixture.sql` 当作测试环境发版 SQL。

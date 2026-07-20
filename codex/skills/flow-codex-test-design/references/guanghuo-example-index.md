# 广火样例索引（结构参考）

维护 skills 时引用；业务 agent 在 glm  monorepo 内按实际路径读取。

| 角色 | 参考路径（glm 根下） |
|------|----------------------|
| 根集成测试设计摘要 | `.flow/changes/guanghuo-wage-register-audit/集成测试设计.md` |
| manifest | `glm-system-test/changes/guanghuo-wage-register-audit/manifest.yaml` |
| test-plan | `glm-system-test/changes/guanghuo-wage-register-audit/test-plan.md` |
| fixtures | `glm-system-test/changes/guanghuo-wage-register-audit/fixtures/` |
| 环境 yml | `glm-system-test/config/services/*/application-system-test.yml` |
| 执行 playbook | `glm-system-test/docs/local-integration-playbook.md` |
| JUnit 包 | `glm-system-test/backend-tests/.../guanghuo/` |

**可复用模式**（非复制内容）：

- 多服务端口：register 7846、worker 7845、contract 7847、agg 9676、wiremock 18080
- agg VM：`-Dregister-feign-var=register-service` + `application-system-test.yml`
- S4 鉴权：Redis db=8，`GjgSessionSupport` + `x-glm-access-token`
- seeds 顺序：release-sql → align-local-schema → seed-fixture
- `apiTestFilter` 分期：`GuanghuoRegister*` → +Contract → +Qrcode/Vendor

新需求须按 as-built 重写，不得整份复制广火 manifest。

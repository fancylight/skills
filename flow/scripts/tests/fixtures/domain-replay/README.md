# Domain verifier replay fixtures

这些夹具与 deterministic `validate-domain-artifact.ps1` 分离。每个 case 同时提供
`domain-model.md`、模拟 schema、代码和 KB 证据，并在 `expected.json` 中记录 DV.4、DV.5、DV.6
的预期结论。replay 测试只验证证据集合和预期路由，不把字符串替换或表格 PASS 宣称为语义审核 PASS。

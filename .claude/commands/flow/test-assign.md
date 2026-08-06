---
name: "Flow: Test Assign"
description: "Dispatch st-api integration test implementer after design verify PASS and controller ISSUE_IMPLEMENTATION_LEASE"
category: Workflow
tags: [workflow, orchestration, testing]
version: "0.1.0"
---

向 system-test 仓派发 `st-api-<change>`。须 controller `next=ISSUE_IMPLEMENTATION_LEASE`；经 `issue-lease` 后才创建 agent。prompt 使用 controller 返回字段，不得自造 lease。

## 前置

1. orchestrator + change_name
2. `/flow:verify full` 无 ERROR
3. 当前轮 `[TEST_VERIFY_RESULT] PASS` design；revision 未漂移
4. ceiling ≥ implementation 且用户本轮明确授权；否则 `STOP_AWAIT_USER_AUTHORIZATION`
5. manifest/test-design/test-plan/fixtures 存在；业务依赖 spec 已完成

## 派发

1. 启动一个 system-test 执行 agent：test-receive → test-apply → test-report
2. REVIEW_REQUEST → 根 `/flow:review` review_mode=test
3. REPORT_REQUEST → 串行 REPORT_LEASE_GRANTED
4. 根不写测试代码、不改业务服务

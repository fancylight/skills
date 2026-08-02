# Domain validation fixture

## 变更决策点
| Decision ID | 问题 | 所需事实 | 判断错误的影响 | 状态 |
|---|---|---|---|---|
| DP-001 | Choose aggregation key | DF-001 | Incorrect aggregation | resolved |

## 领域实体与关系
| 实体/概念 | 关系或职责 | 边界 | 关联 Decision ID |
|---|---|---|---|
| Record | belongs to account | no cross-account merge | DP-001 |

## 领域事实
| Fact ID | 概念 | 精确定义 | 生效条件 | 不生效条件/反例 | 证据 | 影响 Decision ID |
|---|---|---|---|---|---|---|
| DF-001 | record identity | account plus record code identifies one record | account and code are both present | null account does not identify a record | EV-001 | DP-001 |

## 表与字段语义
| 表/接口字段 | 业务语义 | 允许值或类型 | 空值/默认值语义 | 证据 Fact ID |
|---|---|---|---|---|
| record.account | owning account | non-empty string | null is invalid | DF-001 |

## 身份、唯一性、聚合与覆盖规则
| 规则 | 组成字段/前提 | 正例 | 反例或禁止行为 | 证据 Fact ID | 影响 Decision ID |
|---|---|---|---|---|---|
| unique record | account plus code | same account and code merge | null account never merges | DF-001 | DP-001 |

## 状态与转换
| 对象 | 当前状态/条件 | 允许转换或行为 | 禁止转换或行为 | 证据 Fact ID | 影响 Decision ID |
|---|---|---|---|---|---|
| record | active | update owner fields | merge without account | DF-001 | DP-001 |

## 输入、存储与输出转换
| 输入 | 存储/处理 | 输出 | 保持或转换的语义 | 反例 | 证据 Fact ID |
|---|---|---|---|---|---|
| account and code | persist composite identity | record | preserve both values | missing account is rejected | DF-001 |

## 正例、边界与反例
| 场景 | 事实或决策 | 期望 | 不应推断的结论 | 证据 Fact ID |
|---|---|---|---|---|
| complete identity | DF-001 / DP-001 | one aggregate record | null is not a key | DF-001 |

## 证据索引
| Evidence ID | 等级 | 来源 | 定位 | 支撑 Fact ID | 说明 |
|---|---|---|---|---|---|
| EV-001 | E2 | schema definition | schema/record#account-code | DF-001 | composite uniqueness constraint |

## 冲突与未决问题
| 问题 | 冲突证据或缺失证据 | 影响 Decision ID | 所需裁决/补证据 | Evidence ID | 状态 |
|---|---|---|---|---|---|
| none | none | none | none | none | resolved |

## DOMAIN_DRAFT 检查点
- ready for deterministic validation

---
name: analyze-source
description: "Deep source code analysis: trace data flows, map module dependencies, catalog configs/features, and produce a structured technical document with code references and sample data. Use when asked to explain how something works, trace a data pipeline, or document a subsystem."
argument-hint: "[topic or question about the codebase]"
effort: max
---

# Source Code Analysis Skill

You are performing a deep, systematic source code analysis. Your goal is to produce a comprehensive, structured technical document that a new engineer could use to fully understand the topic.

## Input

The user's topic or question: **$ARGUMENTS**

## Analysis Protocol

Follow these phases strictly. Do NOT skip phases or produce shallow summaries.

### Phase 1: Discovery (Breadth-First)

Goal: Map the territory. Identify ALL relevant files before reading any in depth.

1. **Keyword search** — Grep for the topic's key terms (class names, function names, config keys, table names) across the codebase. Record every file that matches.
2. **Entry point identification** — Find where the feature is triggered (CLI script, main function, config loader, API endpoint).
3. **Dependency tracing** — From the entry point, follow imports and function calls to build a call graph. Record each file and line range.
4. **Config discovery** — Search for YAML/JSON/env configs that parameterize the feature. Note the config key paths and default values.
5. **Class inventory (for complex workflows)** — If the call graph spans **≥4 classes across ≥3 files**, or the workflow is OO-heavy (orchestrator/worker/engine/harness/recorder patterns, async pipelines, state machines), explicitly enumerate the collaborating classes. Record for each class: defining file:line, role in one sentence, the class it is called by, the classes it calls/owns. This inventory drives the Mermaid diagrams in Phase 3.

Output a working file list **and** (if applicable) the class inventory before proceeding.

### Phase 2: Deep Read (Depth-First)

Goal: Understand every step in detail.

For each file identified in Phase 1, read the relevant sections and extract:

- **What it does** — One-sentence purpose
- **Key functions/classes** — Name, line range, signature
- **Data in → data out** — What structure enters, what structure exits
- **Config dependencies** — Which config keys affect behavior, with defaults
- **Error handling / edge cases** — Fallbacks, retries, timeouts, defaults

### Phase 3: Synthesis

Goal: Assemble findings into a coherent narrative.

Organize by **data flow** (not by file). Follow the data from input to output, explaining each transformation step.

## Output Document Structure

Produce a Markdown document with these sections. Every section is mandatory unless marked optional.

### Section Template

```
## 1. 概述
- 一句话总结该子系统/流程的作用
- ASCII 架构图或流程图（展示主要组件和数据流向）

## 2. 数据来源
- 列出所有外部数据源（API、数据库、文件、缓存等）
- 每个来源：地址/路径、认证方式、数据格式、刷新频率
- 对应代码引用（文件:行号）
- 对应配置项（YAML key path + 默认值）

## 3. 核心概念 / 字段目录
- 列出所有关键字段/特征/枚举值
- 表格格式：名称 | 来源 | 取值范围 | 含义 | 重要性
- 特殊处理规则（跳过条件、合并逻辑、编码约定）

## 4. 逐步处理流程
对每个 Step：
  ### Step N: 步骤名称
  - **代码**：`文件名:行号范围`（`函数名`）
  - **配置**：相关 YAML 配置项及默认值
  - **逻辑说明**：用文字 + 关键代码片段解释
  - **输入示例**：该步骤接收的数据样例
  - **输出示例**：该步骤产出的数据样例
  - **异常处理**：超时/失败时的降级策略

## 5. 配置参考
- 完整的相关配置块（带注释）
- 环境变量覆盖方式

## 6. 模块间交互（optional）
- 上游如何调用该子系统
- 下游如何消费该子系统的输出
- 反解析/回传逻辑

## 7. 类关系与调用时序（复杂工作流必选，简单流程可省）
触发条件：Phase 1 的类清单 ≥4 个类，或工作流跨 ≥3 个 OO 抽象层（如 orchestrator → engine → worker → recorder）。
本节包含两张 Mermaid 图：
- **类图（classDiagram）**：列出所有参与类的关键属性与方法；用组合/聚合/依赖三类关系连接（`-->` 组合 / `o--` 聚合 / `..>` 依赖）。优先展示"谁拥有谁"和"谁写入谁的字段"。
- **时序图（sequenceDiagram）**：至少覆盖一次完整成功路径；若有重试/失败/降级分支，用 `alt/else` 或 `opt` 展示。Note over 标注每一跳注入到训练样本/下游状态的字段。

## 8. 关键源文件索引
- 表格：文件路径 | 职责 | 关键行号范围
```

### Mermaid 语法避坑（必读——不遵守会导致渲染失败）

我们在实际使用中踩过的坑，写 Mermaid 前先过一遍：

1. **分号是语句分隔符**：`Note over X: foo; bar` 会被拆成两条语句并报 parse error。注释、消息、label 里禁用 `;`，改用 `,` 或 `—`。
2. **participant 别名不要含 `<br/>` / 括号 / 空格**：`participant FW as FSDP Worker<br/>(ActorRolloutRefWorker)` 会挂。用 `participant FW as FSDP_Worker`，需要多行说明另起一条 `Note over FW: ActorRolloutRefWorker`。
3. **消息里少用 Unicode 箭头/符号**：`→ · {} []` 在部分渲染器里触发 lexer 异常。用纯 ASCII，或写成英文单词。
4. **`alt` 只有单分支时换成 `opt`**：`alt cond ... end` 不带 `else` 在某些版本会报错；`opt cond ... end` 更稳。
5. **`else` 分支 label 要简短**：嵌套 `alt/else` 里每个 `else` 后面跟一句简短标签即可，不要塞整段条件表达式。
6. **避免 `autonumber`**：部分环境渲染不稳；编号需求可直接写在消息里（`1. LLM Generate`）。
7. **classDiagram 方法签名**：参数列表里的逗号是合法的；返回类型用空格分隔（`func(x, y) int`）。关系后的 label（`: creates per execute`）可以含空格。
8. **验证手段**：写完后 grep 自己输出，确认 Mermaid 代码块内没有 `;`、没有 `<br/>`、没有 `→/·`；有条件就到 mermaid.live 粘贴一次。

## Sensitive Data Redaction (MANDATORY)

The output document will be shared with team members and potentially stored in wikis. You MUST sanitize all sensitive data before including it in the document.

### Phase 2.5: Sensitivity Scan (runs between Deep Read and Synthesis)

After reading all relevant files, scan your collected notes for sensitive values. Flag and redact before writing the output.

### What counts as sensitive

| Category | Examples | Detection hints |
|----------|---------|-----------------|
| **Secrets & tokens** | API keys, JWT tokens, bearer tokens, passwords, private keys | Strings assigned to vars named `secret`, `token`, `key`, `password`, `credential`, `auth` |
| **Service account credentials** | `servce_account_secret`, `app_key`, `app_secret` | Hardcoded in config files or constructor defaults |
| **Internal URLs with auth** | URLs containing tokens, URLs with embedded credentials | Query params like `?token=`, `?key=`; Basic auth in URL |
| **Internal hostnames** | Full internal domain names (e.g., `xxx.bytedance.net`, `xxx.byteintl.net`) | Domain patterns: `*.bytedance.net`, `*.byteintl.net`, `*.tiktok-row.net` |
| **Redis/DB connection strings** | PSM names, connection URLs with passwords | `redis://`, `mysql://`, vars named `*_psm`, `*_url` with credentials |
| **Environment variables with secrets** | `export SECRET=xxx`, hardcoded env defaults | `os.environ.get("SECRET", "actual_value")` |
| **Hardcoded IDs** | App IDs, user IDs used as defaults, service account names | Constructor defaults, argparse defaults for auth-related params |

### Redaction rules

1. **Secrets / tokens / keys**: Replace the actual value with `<REDACTED>` or a descriptive placeholder.
   - Source code: `servce_account_secret = "fa7d2ae7..."` → write as `servce_account_secret = "<REDACTED>"`
   - Config YAML: `app_key: AdAWYfhH...` → write as `app_key: <REDACTED>`

2. **Internal URLs**: Mask the full hostname but keep the path structure visible.
   - `https://cloud-i18n.bytedance.net/auth/api/v1/jwt` → `https://<internal-auth-service>/auth/api/v1/jwt`
   - `https://holmes-i18n.bytedance.net/api/v1/...` → `https://<holmes-service>/api/v1/...`
   - `https://feeds-common-i18n.byteintl.net/preview` → `https://<sort-service>/preview`

3. **Redis/DB PSMs**: Replace with a generic pattern.
   - `toutiao.redis.agentic_rec.service.my` → `<redis-psm>`

4. **Hardcoded default IDs**: Replace with placeholder but note the parameter name.
   - `app_id = "0F8uQI6JtW4g..."` → `app_id = "<APP_ID>"`
   - `user_name = "liliang.leo"` → `user_name = "<SERVICE_ACCOUNT_USER>"`

5. **Preserve structure, redact values**: The goal is to show the shape of the config/code without leaking secrets.
   ```yaml
   # GOOD — structure visible, values redacted
   trust_press_config:
     x_jwt_token_url: https://<internal-auth-service>/auth/api/v1/jwt
     servce_account_secret: <REDACTED>
     trust_press_url: https://<holmes-service>/api/v1/.../preview-req-ids
   
   # BAD — entire block omitted, reader can't understand the structure
   trust_press_config:
     # (redacted)
   ```

6. **Code snippets**: When quoting source code that contains hardcoded secrets, redact inline.
   ```python
   # GOOD
   response = requests.get(
       "<internal-auth-service>/auth/api/v1/jwt",
       headers={"Authorization": f"Bearer {self.secret}"}  # secret from config
   )
   
   # BAD — leaks the actual secret value
   response = requests.get(
       "https://cloud-i18n.bytedance.net/auth/api/v1/jwt",
       headers={"Authorization": "Bearer fa7d2ae7213f04dd1d8841e0abaa6d1c"}
   )
   ```

### Pre-output checklist

Before finalizing the document, grep your own output for these patterns. If any match, redact them:

- [ ] No literal API keys, tokens, or secrets (strings > 16 chars that look like hashes/keys)
- [ ] No `bytedance.net`, `byteintl.net`, `tiktok-row.net` full hostnames
- [ ] No Redis PSM names or connection strings
- [ ] No hardcoded user names / service account names
- [ ] No `app_id` / `app_key` / `app_secret` actual values
- [ ] No JWT tokens or bearer token values
- [ ] No internal IP addresses or port numbers specific to infrastructure
- [ ] Config examples show structure with `<REDACTED>` placeholders, not real values
- [ ] Code snippets use variable references (e.g., `self.secret`) not literal values

## Quality Standards

- **每个断言都要有代码引用**（`文件名:行号`）。不要凭记忆描述代码行为。
- **示例数据必须逼真且前后一致**。Step N 的输出应该是 Step N+1 的输入，字段值要对得上。
- **配置项引用格式**：`YAML key.path`（`:行号`），附带默认值。
- **不要遗漏错误处理路径**。超时、降级、默认值都要记录。
- **使用中文撰写**（遵循项目 CLAUDE.md 语言规范），代码和配置保持原文。

## Anti-Patterns (Do NOT)

- 不要只列出文件名而不解释它们做什么
- 不要写"该函数处理数据"这样的空话——说明处理了什么数据，怎么处理的
- 不要在没有读过代码的情况下猜测行为
- 不要省略中间步骤让读者自己去猜数据是怎么从 A 到 B 的
- 不要把所有信息堆在一个巨大的段落里——用表格、代码块、列表
- **不要在文档中包含任何敏感信息**——密钥、token、内部域名、服务账号等必须脱敏

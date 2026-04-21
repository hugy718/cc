# 示例输出：训练数据准备流程分析

以下是一个真实分析输出的片段，展示每个 Section 的预期质量。

---

## 示例：Step 描述的标准格式

### Step 3: 特征采集（并发）

**代码**：`rl_data_generator.py:570-692`（`generate_training_samples` + `process_single_sample`）

对每个有效的 `(uid, req_id)` 并发执行三个子步骤，使用 `ThreadPoolExecutor`，最大 `max_processing_workers`（默认128）个线程。

#### Step 3a: 从 service 获取请求级特征

**代码**：`rl_data_generator.py:618-629`

```python
response = session.get(
    "https://hservice-bytedance.net/.../preview-payload",
    params={"req_id": req_id, "psm": "tiktok.recommend.sort_cpp", ...}
)
request_body = json.loads(json.loads(response.text)['data']['request'])
user_os = "android" if "android" in request_body['req_info']['pt'].lower() else "ios"
```

#### Step 3b: 从 Redis 获取用户长期特征

**代码**：`rl_data_generator.py:246-289`

```python
key_str = str(user_id) + "_ulf"
value_str = self.redis_client.get(key_str)  # 例如 "3,0,2,1,1,0,0,0"
values = value_str.strip().split(",")
```

**降级**：Redis 查询失败时返回默认值 `['0', '1', '0', '0', '0', '0', '0', '0']`，最多重试3次，间隔递增（`0.1s * attempt`）。

**输入示例**：
```
uid = "7234567890123"
req_id = "20260416120530abcdef1234567890"
```

**输出示例**：
```json
{
  "user_id": "7234567890123",
  "req_id": "20260416120530abcdef1234567890",
  "os": "android",
  "age": "3",
  "new_user_flag": "0",
  "user_active_days_30d_bucket": "2",
  "user_publish_days_30d_bucket": "1",
  "user_core_interactive_muf_pair_cnt_30d_bucket": "1",
  "user_cold_hot_play_rate_30d_bucket": "0",
  "user_search_pv_30d_bucket": "0",
  "user_valuable_watch_live_duration_30d_bucket": "0",
  "refresh_type": "0",
  "daily_refresh_index": "0",
  "day_of_week": "0",
  "hour_of_day": "2"
}
```

---

## 示例：字段目录的标准格式

| # | 特征名 | 来源 | 取值 | 重要性 | 自然语言映射 |
|---|--------|------|------|--------|-------------|
| 1 | `os` | Holmes | android, ios | 不重要 | 请求来自Android/iOS操作系统 |
| 4 | `user_active_days_30d_bucket` | Redis | 0, 1, 2 | **重要** | 0=app低活跃度, 1=中活跃度, 2=高活跃度 |

---

## 示例：配置参考的标准格式（含脱敏）

```yaml
# GOOD — 结构清晰，敏感值已脱敏
trust_press_config:
  x_jwt_token_url: https://<internal-auth-service>/auth/api/v1/jwt
  servce_account_secret: <REDACTED>
  trust_press_url: https://<holmes-service>/api/v1/.../preview-req-ids
  trust_press_psm: tiktok.recommend.sort_cpp   # PSM 名称保留（非密钥）
  trust_press_page_size: 10000

data:
  streaming_training: True                # 启用流式数据更新
  initial_data_max_wait_time: 10800       # 初始数据最长等待3小时
  streaming_check_interval: 300           # 运行中数据版本检查频率（秒）
  data_generator:
    output_path: .../rollout/data         # Parquet 输出目录
    polling_interval: 6000000             # 轮询间隔（秒）
    train_test_ratio: 0.95                # 训练/测试集比例
    merge_strategy: feature_importance_sampling_merge  # 样本校准策略
    max_sample_size_or_fix_count: 10000   # 校准后最大样本数

redis_client:
  redis_psm: <redis-psm>                 # 脱敏：实际 PSM 名称已替换
  socket_connect_timeout: 250
  socket_timeout: 300

# BAD — 泄露了实际密钥和内部域名
# trust_press_config:
#   servce_account_secret: af7d2ae7213f04dd1d8841e0abaa6c20  ← 绝对不要这样
#   x_jwt_token_url: https://cloud-i18n.bytedance.net/...    ← 内部域名泄露
```

## 示例：代码片段的脱敏处理

```python
# GOOD — 变量引用，不暴露实际值
response = requests.get(
    self.config.x_jwt_token_url,       # URL 来自配置
    headers={"Authorization": f"Bearer {self.secret}"}
)

# BAD — 硬编码的密钥和内部 URL
# response = requests.get(
#     "https://cloud-i18n.bytedance.net/auth/api/v1/jwt",
#     headers={"Authorization": "Bearer fa7d2ae7213f04dd1d8841e0abaa6d1c"}
# )
```

---

## 示例：源文件索引的标准格式

| 文件 | 职责 | 关键行号 |
|------|------|---------|
| `rl_data_generator.py` | 流式数据生成（生产路径） | 222-244, 527-543, 709-736 |
| `utils.py` | 特征→自然语言转换 | 3-90 |
| `rollout/uid_reqid_filter.py` | Sort 服务预过滤 | 100-172, 230-404 |

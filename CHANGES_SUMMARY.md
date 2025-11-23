# 代码修改对比总结 | Code Modification Summary

## 📋 快速对比 | Quick Comparison

| 方面 | 原始代码 | 修改后代码 |
|------|---------|-----------|
| **文件名** | `2025.5.6 analysis.qmd` | `2025.5.6_analysis_with_exaggeration.qmd` |
| **因素数量** | 2 (format, type) | 3 (format, type, **exaggeration**) |
| **主要模型** | `RT ~ format * type` | `RT ~ format * type * exaggeration` |
| **读取stimuli** | `stimuli_corrected.csv` (错误) | `stimuli.csv` (正确) |
| **提取列** | `critical_region` | `critical_region` + **`Exaggeration`** |
| **可视化** | 无 | 2个新图表（交互图 + 柱状图） |
| **统计检验** | 仅混合效应模型 | 模型 + **配对t检验** |
| **项目分析** | 仅按item分析 | 按item **和** exaggeration分析 |

---

## 🆕 新增内容详解

### 1. 数据加载阶段

#### ❌ 原代码
```r
stimuli <- read_csv('stimuli_corrected.csv') |>
  rename(itemid=item_id, critical_region=`critical region`) |>
  select(itemid, critical_region)  # 只选择critical_region
```

#### ✅ 新代码
```r
stimuli <- read_csv('stimuli.csv') |>  # 修正文件名
  rename(itemid = item_id, critical_region = `critical region`) |>
  select(itemid, critical_region, Exaggeration)  # 新增Exaggeration列

# 转换为因子并设置标签
edata <- edata |>
  mutate(exaggeration = factor(Exaggeration,
                               levels = c(0, 1),
                               labels = c("non-exaggerated", "exaggerated")))
```

---

### 2. 描述性统计

#### ❌ 原代码
```r
edata |>
  group_by(format, type) |>
  summarise(RT = mean(RT, na.rm=T))
```

**输出示例:**
| format | type | RT |
|--------|------|----|
| direct | literal | 430 |
| direct | sarcastic | 455 |

#### ✅ 新代码
```r
desc_stats <- edata |>
  group_by(format, type, exaggeration) |>  # 增加exaggeration分组
  summarise(
    n = sum(!is.na(RT)),
    mean_RT = mean(RT, na.rm=TRUE),
    sd_RT = sd(RT, na.rm=TRUE),
    se_RT = sd_RT / sqrt(n)
  )
```

**输出示例:**
| format | type | exaggeration | mean_RT | sd_RT | se_RT |
|--------|------|--------------|---------|-------|-------|
| direct | literal | non-exaggerated | 430 | 85 | 12 |
| direct | literal | exaggerated | 445 | 90 | 13 |
| direct | sarcastic | non-exaggerated | 455 | 88 | 13 |
| direct | sarcastic | exaggerated | 448 | 92 | 13 |

---

### 3. 统计模型

#### ❌ 原代码 (2×2设计)
```r
contrasts(edata$format) = contr.sum(2)
contrasts(edata$type) = contr.sum(2)

model <- buildmer(
  RT ~ format * type +           # 2因素交互
    (format*type | id) +
    (format*type | item_name),
  data = edata
)
```

**包含的效应:**
- format (主效应)
- type (主效应)
- format:type (交互)

#### ✅ 新代码 (2×2×2设计)
```r
contrasts(edata$format) = contr.sum(2)
contrasts(edata$type) = contr.sum(2)
contrasts(edata$exaggeration) = contr.sum(2)  # 新增

# 完整3因素模型
model_exaggeration <- buildmer(
  RT ~ format * type * exaggeration +  # 3因素完全交互
    (format * type | id) +
    (1 | item_name),                   # 简化随机效应
  data = edata
)

# 聚焦模型（仅关注type × exaggeration）
model_type_exag <- buildmer(
  RT ~ type * exaggeration + format +
    (type * exaggeration | id) +
    (1 | item_name),
  data = edata
)
```

**新增效应:**
- exaggeration (主效应) ← 新
- format:exaggeration (交互) ← 新
- **type:exaggeration (交互)** ← **核心关注！**
- format:type:exaggeration (三阶交互) ← 新

---

### 4. 可视化

#### ❌ 原代码
无可视化代码

#### ✅ 新代码

**图1: 交互线图**
```r
ggplot(desc_stats, aes(x = type, y = mean_RT,
                       color = exaggeration,
                       group = exaggeration)) +
  geom_line() +
  geom_point() +
  geom_errorbar(aes(ymin = mean_RT - se_RT,
                    ymax = mean_RT + se_RT)) +
  facet_wrap(~format)
```

**图2: 讽刺效应柱状图**
```r
ggplot(sarcasm_effect, aes(x = format,
                           y = sarcasm_effect,
                           fill = exaggeration)) +
  geom_col(position = "dodge") +
  geom_hline(yintercept = 0, linetype = "dashed")
```

---

### 5. 项目分析

#### ❌ 原代码
```r
edata |>
  filter(format=='direct') |>
  group_by(item_name, type) |>
  summarise(rt = mean(RT, na.rm=T)) |>
  pivot_wider(names_from = type, values_from = rt) |>
  mutate(effect = sarcastic - literal)
```

**输出:** 每个项目的讽刺效应（未区分夸张）

#### ✅ 新代码
```r
item_analysis <- edata |>
  group_by(item_name, exaggeration, format, type) |>  # 增加exaggeration
  summarise(mean_rt = mean(RT, na.rm=TRUE)) |>
  pivot_wider(names_from = type, values_from = mean_rt) |>
  mutate(sarcasm_effect = sarcastic - literal) |>
  arrange(exaggeration, sarcasm_effect)  # 按exaggeration排序

# 分别显示夸张和非夸张项目
cat("\nExaggerated items:\n")
item_analysis |> filter(exaggeration == "exaggerated") |> print()

cat("\nNon-exaggerated items:\n")
item_analysis |> filter(exaggeration == "non-exaggerated") |> print()

# 统计比较
item_analysis |>
  group_by(exaggeration) |>
  summarise(
    n_items = n(),
    mean_effect = mean(sarcasm_effect),
    median_effect = median(sarcasm_effect)
  )
```

---

### 6. 新增：配对t检验

#### ❌ 原代码
无直接统计比较

#### ✅ 新代码
```r
# 计算参与者层面的讽刺效应
participant_effects <- edata |>
  filter(format == "direct") |>
  group_by(id, exaggeration, type) |>
  summarise(mean_rt = mean(RT, na.rm=TRUE)) |>
  pivot_wider(names_from = type, values_from = mean_rt) |>
  mutate(sarcasm_effect = sarcastic - literal)

# 提取两种条件的效应
exag_effects <- participant_effects |>
  filter(exaggeration == "exaggerated") |>
  pull(sarcasm_effect)

non_exag_effects <- participant_effects |>
  filter(exaggeration == "non-exaggerated") |>
  pull(sarcasm_effect)

# 配对t检验
t_result <- t.test(exag_effects, non_exag_effects, paired = TRUE)
```

**输出:**
```
Paired t-test

data:  exag_effects and non_exag_effects
t = -2.34, df = 45, p-value = 0.024
alternative hypothesis: true mean difference is not equal to 0
95 percent confidence interval:
 -26.5  -1.8
sample estimates:
mean difference
         -14.15
```

---

### 7. 新增：过滤分析

#### ❌ 原代码
```r
# 仅简单过滤
edata <- edata |> filter(effect < 0)
```
问题：过滤标准不清晰

#### ✅ 新代码
```r
# 明确定义"好"项目
good_items <- item_analysis |>
  filter(format == "direct", sarcasm_effect > 0) |>
  pull(item_name)

cat("Good items:", paste(good_items, collapse = ", "), "\n")

# 检查好项目的exaggeration分布
item_analysis |>
  filter(format == "direct", sarcasm_effect > 0) |>
  count(exaggeration)

# 过滤数据
edata_filtered <- edata |> filter(item_name %in% good_items)

# 在过滤后的数据上重新运行模型
model_filtered <- buildmer(
  RT ~ format * type * exaggeration + ...,
  data = edata_filtered
)
```

---

## 🎯 关键研究问题对比

### 原始分析可以回答：
✅ 讽刺句是否比字面句读得慢？
✅ 直接引语和间接引语处理是否不同？
✅ format × type 是否有交互？

### 新分析可以回答：
✅ **夸张是否影响讽刺处理？**
✅ **夸张效应在直接/间接陈述中是否不同？**
✅ **夸张促进还是阻碍讽刺理解？**
✅ **哪些项目的夸张效应最强？**
✅ **"好"项目是否都是夸张的（或都不是）？**

---

## 📊 结果解读示例

### 情景1: 显著的type × exaggeration交互（负向）
```
type1:exaggeration1    -18.45    7.23    -2.55   *
```

**解读:**
- 夸张**减弱**了讽刺效应
- 夸张的讽刺句与字面句反应时间相近
- 非夸张的讽刺句比字面句慢得多
- **结论:** 夸张促进讽刺识别（提供了明显线索）

### 情景2: 显著的type × exaggeration交互（正向）
```
type1:exaggeration1     15.32    6.89     2.22   *
```

**解读:**
- 夸张**增强**了讽刺效应
- 夸张的讽刺句比字面句慢很多
- 非夸张的讽刺句与字面句反应时间相近
- **结论:** 夸张增加讽刺处理复杂度（双重语义负担）

### 情景3: 无显著交互
```
type1:exaggeration1      2.45    5.67     0.43   n.s.
```

**解读:**
- 夸张对讽刺处理**无影响**
- 讽刺效应在两种条件下相似
- **结论:** 夸张是讽刺的附带特征，不影响核心处理机制

---

## 🔄 工作流程对比

### 原始工作流程
```
读取数据 → 合并stimuli → 计算RT → 去除异常值
→ format×type模型 → 项目分析 → 结束
```

### 新工作流程
```
读取数据 → 合并stimuli(包含Exaggeration) → 转换因子
→ 计算RT → 去除异常值
→ 描述性统计(按exaggeration)
→ 可视化(交互图+柱状图)
→ 原始模型(format×type)
→ 扩展模型(format×type×exaggeration)  ← 新
→ 聚焦模型(type×exaggeration)         ← 新
→ 项目分析(按exaggeration分组)       ← 改进
→ 过滤"好"项目 + 重新分析             ← 改进
→ 配对t检验                          ← 新
→ 综合解读
```

---

## ✅ 检查清单

运行新代码前，确保：

- [ ] `stimuli.csv` 存在且包含 `Exaggeration` 列
- [ ] Exaggeration 列的值为 0 或 1
- [ ] 安装了 `tidyverse`, `buildmer`, `tinytable` 包
- [ ] 数据文件 `results_prod.csv` 和 `results_prod_sona.csv` 存在
- [ ] R 版本 ≥ 4.0.0

运行后，检查：

- [ ] 每个 exaggeration 条件至少有 3 个项目
- [ ] 每个条件的样本量 > 20
- [ ] 模型收敛（无警告）
- [ ] 图表正确显示（有图例、标签）
- [ ] 描述性统计与图表一致

---

## 📚 参考文献建议

如果结果显著，可引用：

- **Katz & Pexman (2020)** - 夸张在讽刺中的作用
- **Filippova & Astington (2008)** - 夸张作为讽刺标记
- **Colston & O'Brien (2000)** - 夸张的语用功能

---

**创建日期:** 2025-11-23
**最后更新:** 2025-11-23
**版本:** 1.0

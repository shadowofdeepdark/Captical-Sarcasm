# 分析Exaggeration效果的R脚本
# 加载必要的库
library(tidyverse)
library(lme4)
library(lmerTest)

# 读取数据
cat("正在加载数据...\n")
stimuli <- read.csv("stimuli.csv", stringsAsFactors = FALSE)
results <- read.csv("results_prod_sona.csv", comment.char = "#", stringsAsFactors = FALSE)

# 查看数据结构
cat("\n刺激材料数据维度:", dim(stimuli), "\n")
cat("结果数据维度:", dim(results), "\n")

# 提取列名
cat("\n结果数据列名:\n")
print(names(results))

# 查看前几行
cat("\nStimuli数据概览:\n")
print(head(stimuli))

# 检查Exaggeration列
cat("\nExaggeration变量分布:\n")
print(table(stimuli$Exaggeration))

# 提取阅读时间数据
# 查找Key按键反应时间数据
cat("\n正在提取阅读时间数据...\n")
rt_data <- results %>%
  filter(PennElementType == "Key") %>%
  select(MD5.hash.of.participant.s.IP.address.,
         Order.number.of.item.,
         Label,
         Parameter,
         Value,
         EventTime,
         sonaID) %>%
  rename(participant = MD5.hash.of.participant.s.IP.address.,
         item_order = Order.number.of.item.,
         label = Label,
         parameter = Parameter,
         value = Value,
         event_time = EventTime,
         sona_id = sonaID)

cat("提取的阅读时间数据行数:", nrow(rt_data), "\n")

# 提取item_id从label
rt_data <- rt_data %>%
  mutate(item_id = str_extract(label, "[^_]+_[^_]+_[^_]+"))

# 与stimuli合并
cat("\n正在合并刺激材料信息...\n")
merged_data <- rt_data %>%
  left_join(stimuli, by = "item_id")

cat("合并后的数据行数:", nrow(merged_data), "\n")

# 只保留实验项目(exp)
exp_data <- merged_data %>%
  filter(type == "exp")

cat("实验条件数据行数:", nrow(exp_data), "\n")

# 计算每个critical region的阅读时间
# 提取region number from parameter
exp_data <- exp_data %>%
  mutate(region = as.numeric(str_extract(parameter, "^\\d+")))

# 计算阅读时间(相邻事件的时间差)
exp_data <- exp_data %>%
  arrange(participant, item_order, region) %>%
  group_by(participant, item_order) %>%
  mutate(rt = c(NA, diff(event_time))) %>%
  ungroup()

# 只保留critical region (根据stimuli中的critical region列)
# 首先查看critical region的值
cat("\nCritical region分布:\n")
print(table(exp_data$critical.region))

# 过滤掉异常值(RT < 100ms 或 RT > 5000ms)
exp_data_clean <- exp_data %>%
  filter(!is.na(rt)) %>%
  filter(rt >= 100 & rt <= 5000) %>%
  filter(region == critical.region)

cat("\n清理后的数据行数:", nrow(exp_data_clean), "\n")

# 描述性统计
cat("\n===== 描述性统计 =====\n")
desc_stats <- exp_data_clean %>%
  group_by(Exaggeration, format) %>%
  summarise(
    n = n(),
    mean_rt = mean(rt, na.rm = TRUE),
    sd_rt = sd(rt, na.rm = TRUE),
    se_rt = sd_rt / sqrt(n),
    .groups = "drop"
  )

print(desc_stats)

# 可视化
cat("\n正在生成可视化图表...\n")
p <- ggplot(exp_data_clean, aes(x = as.factor(Exaggeration), y = rt, fill = as.factor(Exaggeration))) +
  geom_boxplot(alpha = 0.7) +
  geom_jitter(width = 0.2, alpha = 0.3) +
  facet_wrap(~format) +
  labs(
    title = "阅读时间按Exaggeration和Format分组",
    x = "Exaggeration (0=Literal, 1=Sarcastic)",
    y = "阅读时间 (ms)",
    fill = "Exaggeration"
  ) +
  theme_minimal() +
  theme(text = element_text(size = 12))

ggsave("exaggeration_effect_boxplot.png", p, width = 10, height = 6, dpi = 300)
cat("图表已保存到: exaggeration_effect_boxplot.png\n")

# 统计分析 - 线性混合效应模型
cat("\n===== 统计分析 =====\n")
cat("正在拟合线性混合效应模型...\n")

# 对数转换阅读时间以接近正态分布
exp_data_clean <- exp_data_clean %>%
  mutate(log_rt = log(rt))

# 中心化和标准化预测变量
exp_data_clean <- exp_data_clean %>%
  mutate(
    Exaggeration_c = scale(Exaggeration, center = TRUE, scale = FALSE),
    format_numeric = ifelse(format == "direct", -0.5, 0.5),
    format_c = scale(format_numeric, center = TRUE, scale = FALSE)
  )

# 拟合模型
# 模型1: 只有Exaggeration作为固定效应
model1 <- lmer(log_rt ~ Exaggeration_c + (1 | participant) + (1 | item_id),
               data = exp_data_clean,
               REML = FALSE)

cat("\n模型1: Exaggeration主效应\n")
print(summary(model1))

# 模型2: Exaggeration + Format
model2 <- lmer(log_rt ~ Exaggeration_c + format_c + (1 | participant) + (1 | item_id),
               data = exp_data_clean,
               REML = FALSE)

cat("\n模型2: Exaggeration + Format\n")
print(summary(model2))

# 模型3: 包含交互作用
model3 <- lmer(log_rt ~ Exaggeration_c * format_c + (1 | participant) + (1 | item_id),
               data = exp_data_clean,
               REML = FALSE)

cat("\n模型3: Exaggeration × Format 交互作用\n")
print(summary(model3))

# 模型比较
cat("\n模型比较:\n")
print(anova(model1, model2, model3))

# 提取Exaggeration效应的统计信息
cat("\n===== EXAGGERATION 效应总结 =====\n")
coef_table <- summary(model3)$coefficients
exag_row <- coef_table["Exaggeration_c", ]

cat(sprintf("\nExaggeration 效应:\n"))
cat(sprintf("  系数 (Coefficient): %.4f\n", exag_row["Estimate"]))
cat(sprintf("  标准误 (SE): %.4f\n", exag_row["Std. Error"]))
cat(sprintf("  t值: %.4f\n", exag_row["t value"]))
cat(sprintf("  p值: %.4f\n", exag_row["Pr(>|t|)"]))

if (exag_row["Pr(>|t|)"] < 0.001) {
  cat("\n结论: Exaggeration有 ***极其显著*** 的效果 (p < 0.001)\n")
} else if (exag_row["Pr(>|t|)"] < 0.01) {
  cat("\n结论: Exaggeration有 **非常显著** 的效果 (p < 0.01)\n")
} else if (exag_row["Pr(>|t|)"] < 0.05) {
  cat("\n结论: Exaggeration有 *显著* 的效果 (p < 0.05)\n")
} else {
  cat("\n结论: Exaggeration 没有显著效果 (p >= 0.05)\n")
}

# 计算效应量
# 对于线性回归,可以计算标准化系数作为效应量
cat(sprintf("\n效应量 (标准化系数): %.4f\n", exag_row["Estimate"]))

# 保存结果
cat("\n正在保存分析结果...\n")
write.csv(desc_stats, "descriptive_statistics.csv", row.names = FALSE)
write.csv(coef_table, "model_coefficients.csv")
cat("描述性统计已保存到: descriptive_statistics.csv\n")
cat("模型系数已保存到: model_coefficients.csv\n")

cat("\n分析完成!\n")

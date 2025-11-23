#!/usr/bin/env Rscript

# Sarcasm Analysis with Separate Exaggeration Models
# This script runs the analysis and outputs results

cat("\n========================================\n")
cat("Loading packages...\n")
cat("========================================\n\n")

library(dplyr)
library(tidyr)
library(readr)
library(stringr)
library(lme4)

options(digits = 2, scipen = 2)

cat("Packages loaded successfully!\n\n")

# ============================================
# 1. READ AND TIDY DATA
# ============================================

cat("========================================\n")
cat("1. READING AND TIDYING DATA\n")
cat("========================================\n\n")

## Read files line-by-line from BOTH SONA and Prolific data
ldata <- c(read_lines('results_prod_sona.csv'), read_lines('prolific_results.csv'))
cat("Data sources:\n")
cat(" - SONA data: results_prod_sona.csv\n")
cat(" - Prolific data: prolific_results.csv\n\n")

## Get age data
adata <- str_subset(ldata,'age,.*EnterReturn')
adata <- read_csv(I(adata),
                  col_types='cc________i___',
                  col_names=c('fintime','ipsum','age'),
                  show_col_types = FALSE)

## Remove duplicates
adata <- adata %>%
  group_by(fintime, ipsum) %>%
  mutate(occurrence_number = row_number()) %>%
  ungroup() %>%
  filter(occurrence_number != 2) %>%
  select(-occurrence_number)

cat("Age data loaded:", nrow(adata), "participants\n")

## Get experimental data
edata <- str_subset(ldata,'exp,.*Key')
edata <- read_csv(I(edata),
               col_types='cc_i____c__d_cc__',
               col_names=c('fintime','ipsum','event','region','timestamp','itemid','group'),
               show_col_types = FALSE)

## Use LEFT JOIN to keep all experimental data, even without age
edata <- left_join(edata, adata, by = c("fintime", "ipsum"))
edata <- edata %>% mutate(id=paste0(fintime,ipsum), .before=event, .keep="unused")

cat("Experimental data loaded:", nrow(edata), "observations\n")
cat("Participants with age data:", sum(!is.na(edata$age) & edata$age > 0), "unique IDs\n")
cat("Participants without age data:", sum(is.na(edata$age) | edata$age == 0), "observations\n")

## Get question data
qdata <- str_subset(ldata, coll('Question'))
qdata <- str_replace(qdata,'(filler_[0-9]+)','\\1,"FILL"')
qdata <- str_replace(qdata,',$','')

qdata <- read_csv(I(qdata),
               col_types='cc_i_____cc__c_i__',
               col_names=c('fintime','ipsum','event','question','answer','itemid','keypress'),
               show_col_types = FALSE)

## Calculate accuracy
qdata <- qdata %>% mutate(CORRECT=case_when(
  answer=='Yes' & keypress==1 ~ 1,
  answer=='No'  & keypress==0 ~ 1,
  .default = 0
))

qdata <- qdata %>% mutate(id=paste0(fintime,ipsum), .before=event, .keep="unused")
qa <- qdata %>% group_by(id) %>% summarise(accuracy=mean(CORRECT))
edata <- left_join(edata, qa, by = "id")

cat("Question accuracy calculated\n")

## Split itemid
edata <- edata %>% separate_wider_delim(itemid,'_',
                                       names=c('item_name','format','type'),
                                       cols_remove=FALSE)

edata <- edata %>% mutate(
  format = case_match(format, 'ind' ~ 'indirect', 'dir' ~ 'direct', .default = 'ERROR'),
  type = case_match(type, 'lit' ~ 'literal', 'sarc' ~ 'sarcastic', .default = 'ERROR')
)

## Calculate RT
edata <- edata %>%
  group_by(id,item_name) %>%
  mutate(prevtime=lag(timestamp), prev2time=lag(timestamp,n=2)) %>%
  mutate(RT=timestamp-prevtime, R2T=timestamp-prev2time) %>%
  select(-c(timestamp,prevtime,prev2time)) %>%
  filter(!str_detect(region,'-start$')) %>%
  ungroup()

cat("RT calculated\n\n")

# ============================================
# 2. LOAD STIMULI AND EXAGGERATION
# ============================================

cat("========================================\n")
cat("2. LOADING STIMULI WITH EXAGGERATION\n")
cat("========================================\n\n")

stimuli <- read_csv('stimuli.csv', show_col_types = FALSE) %>%
  rename(itemid = item_id, critical_region = `critical region`) %>%
  select(itemid, critical_region, Exaggeration)

edata <- left_join(edata, stimuli, by = "itemid")

edata <- edata %>%
  mutate(exaggeration = factor(Exaggeration,
                               levels = c(0, 1),
                               labels = c("non-exaggerated", "exaggerated")))

cat("Distribution of items by exaggeration:\n")
edata %>%
  distinct(item_name, exaggeration) %>%
  count(exaggeration) %>%
  print()

cat("\n")

# ============================================
# 3. CALCULATE RESIDUAL RT
# ============================================

cat("========================================\n")
cat("3. CALCULATING RESIDUAL RT\n")
cat("========================================\n\n")

edata <- edata %>%
  separate_wider_delim(region,'-', names=c('region','text'), too_many='merge') %>%
  mutate(region=as.numeric(region)+1, text=URLdecode(text), text_len=str_length(text), .after=text)

CRITICAL_LENGTH=1000

do_reg <- function(y,x) {
  m <- lm(y~x, subset=x < CRITICAL_LENGTH)
  return(coef(m))
}

coefs <- edata %>%
  group_by(id) %>%
  summarise(c=do_reg(RT,text_len)[1], m=do_reg(RT,text_len)[2])

edata <- left_join(edata, coefs, by = "id")

cat("Residual RT coefficients calculated\n\n")

# ============================================
# 4. OUTLIER DETECTION
# ============================================

outliers <- function(x, sds=2.5) {
  bound <- sds*sd(x, na.rm=TRUE)
  m <- mean(x, na.rm=TRUE)
  return(abs(x-m) > bound)
}

# ============================================
# 5. FILTER AND CLEAN
# ============================================

cat("========================================\n")
cat("4. FILTERING AND CLEANING DATA\n")
cat("========================================\n\n")

# Filter to critical region only (keep all ages)
edata <- edata %>% filter(region==critical_region)

cat("Filtered to critical region (all ages)\n")
cat("Total observations:", nrow(edata), "\n")
cat("Unique participants:", n_distinct(edata$id), "\n")
cat("  - With age data:", sum(!is.na(edata$age)), "observations\n")
cat("  - Without age data:", sum(is.na(edata$age)), "observations\n\n")

edata <- edata %>% mutate(RRT=RT - (m*text_len+c))

# Remove RTs < 200ms
edata <- edata %>% mutate(RT=ifelse(RT<200,NA,RT))
l200 <- sum(is.na(edata$RT))

# Remove outliers
edata <- edata %>%
  group_by(id) %>%
  mutate(outlier=outliers(RT, sds=3)) %>%
  ungroup()

o3 <- sum(edata$outlier, na.rm=T)

edata <- edata %>%
  group_by(id) %>%
  mutate(ol2=outliers(RRT, sds=3)) %>%
  ungroup()

o23 <- sum(edata$ol2, na.rm=T)

# Apply filters
edata <- edata %>%
  mutate(RT=ifelse(outlier,NA,RT)) %>%
  mutate(RRT=ifelse(ol2,NA,RRT))

cat("Data cleaning summary:\n")
cat(" -", l200, "RTs removed (< 200ms)\n")
cat(" -", o3, "outliers removed (RT > 3 SDs)\n")
cat(" -", o23, "outliers removed (RRT > 3 SDs)\n\n")

# ============================================
# 6. DESCRIPTIVE STATISTICS
# ============================================

cat("========================================\n")
cat("5. DESCRIPTIVE STATISTICS\n")
cat("========================================\n\n")

desc_stats <- edata %>%
  group_by(format, type, exaggeration) %>%
  summarise(
    n = sum(!is.na(RT)),
    mean_RT = mean(RT, na.rm=TRUE),
    sd_RT = sd(RT, na.rm=TRUE),
    se_RT = sd_RT / sqrt(n),
    .groups = "drop"
  )

cat("Mean RT by Format, Type, and Exaggeration:\n")
print(desc_stats, n = 100)
cat("\n")

cat("Sarcasm Effect (Sarcastic - Literal) by Exaggeration:\n")
sarcasm_effect <- desc_stats %>%
  select(format, type, exaggeration, mean_RT) %>%
  pivot_wider(names_from = type, values_from = mean_RT) %>%
  mutate(sarcasm_effect = sarcastic - literal) %>%
  arrange(exaggeration, format)

print(sarcasm_effect, n = 100)
cat("\n")

# ============================================
# 7. STATISTICAL MODELS
# ============================================

cat("========================================\n")
cat("6. STATISTICAL MODELS\n")
cat("========================================\n\n")

# Prepare factors
edata <- edata %>%
  mutate(
    format = as.factor(format),
    type = as.factor(type),
    exaggeration = as.factor(exaggeration)
  )

contrasts(edata$format) <- contr.sum(2)
contrasts(edata$type) <- contr.sum(2)
contrasts(edata$exaggeration) <- contr.sum(2)

cat("--- MODEL 1: Full 3-Way Interaction ---\n")
cat("Formula: RT ~ format * type * exaggeration\n\n")

# Try full model first, then simplify if needed
tryCatch({
  model_full <- lmer(
    RT ~ format * type * exaggeration +
      (1 | id) +
      (1 | item_name),
    data = edata,
    control = lmerControl(optimizer = "bobyqa")
  )
  cat("Full model converged!\n\n")
  print(summary(model_full))
  cat("\n\n")
}, error = function(e) {
  cat("Full model failed:", e$message, "\n\n")
})

# ============================================
# 8. SEPARATE MODELS BY EXAGGERATION
# ============================================

cat("========================================\n")
cat("7. SEPARATE MODELS FOR EACH EXAGGERATION CONDITION\n")
cat("========================================\n\n")

cat("--- MODEL 2A: EXAGGERATED ITEMS ONLY ---\n\n")

edata_exag <- edata %>% filter(exaggeration == "exaggerated")

cat("Sample size (exaggerated):\n")
cat(" - Observations:", nrow(edata_exag), "\n")
cat(" - Participants:", n_distinct(edata_exag$id), "\n")
cat(" - Items:", n_distinct(edata_exag$item_name), "\n\n")

cat("Descriptive Statistics (Exaggerated):\n")
desc_exag <- edata_exag %>%
  group_by(format, type) %>%
  summarise(
    n = sum(!is.na(RT)),
    mean_RT = mean(RT, na.rm=TRUE),
    sd_RT = sd(RT, na.rm=TRUE),
    .groups = "drop"
  )
print(desc_exag)
cat("\n")

cat("Sarcasm Effect (Exaggerated):\n")
effect_exag <- desc_exag %>%
  select(format, type, mean_RT) %>%
  pivot_wider(names_from = type, values_from = mean_RT) %>%
  mutate(sarcasm_effect = sarcastic - literal)
print(effect_exag)
cat("\n")

# Run model
tryCatch({
  model_exag <- lmer(
    RT ~ format * type +
      (1 | id) +
      (1 | item_name),
    data = edata_exag,
    control = lmerControl(optimizer = "bobyqa")
  )
  cat("Model Summary (Exaggerated Items):\n")
  print(summary(model_exag))
  cat("\n\n")
}, error = function(e) {
  cat("Model failed:", e$message, "\n\n")
})

cat("========================================\n")
cat("--- MODEL 2B: NON-EXAGGERATED ITEMS ONLY ---\n\n")

edata_nonexag <- edata %>% filter(exaggeration == "non-exaggerated")

cat("Sample size (non-exaggerated):\n")
cat(" - Observations:", nrow(edata_nonexag), "\n")
cat(" - Participants:", n_distinct(edata_nonexag$id), "\n")
cat(" - Items:", n_distinct(edata_nonexag$item_name), "\n\n")

cat("Descriptive Statistics (Non-Exaggerated):\n")
desc_nonexag <- edata_nonexag %>%
  group_by(format, type) %>%
  summarise(
    n = sum(!is.na(RT)),
    mean_RT = mean(RT, na.rm=TRUE),
    sd_RT = sd(RT, na.rm=TRUE),
    .groups = "drop"
  )
print(desc_nonexag)
cat("\n")

cat("Sarcasm Effect (Non-Exaggerated):\n")
effect_nonexag <- desc_nonexag %>%
  select(format, type, mean_RT) %>%
  pivot_wider(names_from = type, values_from = mean_RT) %>%
  mutate(sarcasm_effect = sarcastic - literal)
print(effect_nonexag)
cat("\n")

# Run model
tryCatch({
  model_nonexag <- lmer(
    RT ~ format * type +
      (1 | id) +
      (1 | item_name),
    data = edata_nonexag,
    control = lmerControl(optimizer = "bobyqa")
  )
  cat("Model Summary (Non-Exaggerated Items):\n")
  print(summary(model_nonexag))
  cat("\n\n")
}, error = function(e) {
  cat("Model failed:", e$message, "\n\n")
})

# ============================================
# 9. PAIRED T-TEST
# ============================================

cat("========================================\n")
cat("8. PAIRED T-TEST: EXAGGERATED vs NON-EXAGGERATED\n")
cat("========================================\n\n")

participant_effects <- edata %>%
  filter(format == "direct") %>%
  group_by(id, exaggeration, type) %>%
  summarise(mean_rt = mean(RT, na.rm=TRUE), .groups = "drop") %>%
  pivot_wider(names_from = type, values_from = mean_rt) %>%
  mutate(sarcasm_effect = sarcastic - literal)

exag_effects <- participant_effects %>%
  filter(exaggeration == "exaggerated") %>%
  pull(sarcasm_effect)

nonexag_effects <- participant_effects %>%
  filter(exaggeration == "non-exaggerated") %>%
  pull(sarcasm_effect)

cat("N participants:", min(length(exag_effects), length(nonexag_effects)), "\n\n")

t_result <- t.test(exag_effects, nonexag_effects, paired = TRUE)
print(t_result)
cat("\n")

cat("Mean sarcasm effect (exaggerated):    ", mean(exag_effects, na.rm=TRUE), "ms\n")
cat("Mean sarcasm effect (non-exaggerated):", mean(nonexag_effects, na.rm=TRUE), "ms\n")
cat("Difference:                            ",
    mean(exag_effects, na.rm=TRUE) - mean(nonexag_effects, na.rm=TRUE), "ms\n\n")

# ============================================
# 10. SUMMARY
# ============================================

cat("========================================\n")
cat("ANALYSIS COMPLETE!\n")
cat("========================================\n\n")

cat("Key findings to check:\n")
cat("1. Descriptive statistics show RT patterns by exaggeration\n")
cat("2. Full model tests 3-way interaction\n")
cat("3. Separate models show if format×type pattern differs\n")
cat("4. T-test directly compares sarcasm effects\n\n")

cat("Interpretation:\n")
cat("- Smaller effect in exaggerated → facilitation\n")
cat("- Larger effect in exaggerated → interference\n")
cat("- Similar effects → no modulation\n\n")

cat("========================================\n\n")

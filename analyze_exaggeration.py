#!/usr/bin/env python3
"""
分析Exaggeration效果的Python脚本
"""

import pandas as pd
import numpy as np
from scipy import stats
import matplotlib.pyplot as plt
import seaborn as sns

print("正在加载数据...")
# 读取刺激材料数据
stimuli = pd.read_csv('stimuli.csv')
print(f"刺激材料数据维度: {stimuli.shape}")

# 读取结果数据 - 手动指定列名
column_names = [
    'time_received',
    'participant_hash',
    'controller',
    'item_order',
    'element_number',
    'Label',
    'group',
    'PennElementType',
    'PennElementName',
    'Parameter',
    'Value',
    'EventTime',
    'sonaID',
    'Comments'
]

# 使用results_prod.csv文件(包含实际实验数据)
results = pd.read_csv('results_prod.csv', comment='#', names=column_names,
                     on_bad_lines='skip', skiprows=0)
print(f"结果数据维度 (results_prod.csv): {results.shape}")

# 查看Exaggeration变量分布
print("\nExaggeration变量分布:")
print(stimuli['Exaggeration'].value_counts())

# 提取阅读时间数据
print("\n正在提取阅读时间数据...")
rt_data = results[results['PennElementType'] == 'Key'].copy()
print(f"按键数据行数: {len(rt_data)}")

# 重命名列
rt_data = rt_data.rename(columns={
    'participant_hash': 'participant',
    'Label': 'label',
    'Parameter': 'parameter',
    'Value': 'value',
    'EventTime': 'event_time',
    'sonaID': 'sona_id'
})

# 提取item_id
rt_data['item_id'] = rt_data['label'].str.extract(r'([^_]+_[^_]+_[^_]+)')[0]

# 调试信息
print("\n调试: 提取的item_id示例:")
print(rt_data['item_id'].dropna().unique()[:5])
print("\n调试: stimuli中的item_id示例:")
print(stimuli['item_id'].unique()[:5])
print(f"\nrt_data中唯一item_id数量: {rt_data['item_id'].nunique()}")
print(f"stimuli中唯一item_id数量: {stimuli['item_id'].nunique()}")

# 合并stimuli信息
print("\n正在合并刺激材料信息...")
merged_data = rt_data.merge(stimuli, on='item_id', how='left')
print(f"合并后的数据行数: {len(merged_data)}")
print(f"成功匹配stimuli的行数: {merged_data['type'].notna().sum()}")

# 只保留实验项目
exp_data = merged_data[merged_data['type'] == 'exp'].copy()
print(f"实验条件数据行数: {len(exp_data)}")

# 提取region number
exp_data['region'] = exp_data['parameter'].str.extract(r'^(\d+)')[0].astype(float)

# 计算阅读时间
print("\n正在计算阅读时间...")
exp_data = exp_data.sort_values(['participant', 'item_order', 'region'])
exp_data['rt'] = exp_data.groupby(['participant', 'item_order'])['event_time'].diff()

# 过滤异常值
# 注意: 列名是'critical region'(有空格)
exp_data_clean = exp_data[
    (exp_data['rt'].notna()) &
    (exp_data['rt'] >= 100) &
    (exp_data['rt'] <= 5000) &
    (exp_data['region'] == exp_data['critical region'])
].copy()

print(f"\n清理后的数据行数: {len(exp_data_clean)}")

# 描述性统计
print("\n===== 描述性统计 =====")
desc_stats = exp_data_clean.groupby(['Exaggeration', 'format'])['rt'].agg([
    ('n', 'count'),
    ('mean', 'mean'),
    ('sd', 'std'),
    ('se', lambda x: x.std() / np.sqrt(len(x)))
]).reset_index()

print(desc_stats)
desc_stats.to_csv('descriptive_statistics.csv', index=False)

# 可视化
print("\n正在生成可视化图表...")
plt.figure(figsize=(12, 6))
sns.boxplot(data=exp_data_clean, x='Exaggeration', y='rt', hue='format')
plt.title('Reading Time by Exaggeration and Format')
plt.xlabel('Exaggeration (0=Literal, 1=Sarcastic)')
plt.ylabel('Reading Time (ms)')
plt.legend(title='Format')
plt.tight_layout()
plt.savefig('exaggeration_effect_boxplot.png', dpi=300)
print("图表已保存到: exaggeration_effect_boxplot.png")

# 统计分析
print("\n===== 统计分析 =====")

# 1. 整体Exaggeration效果 (t检验)
print("\n1. Exaggeration主效应 (配对t检验):")
literal_rt = exp_data_clean[exp_data_clean['Exaggeration'] == 0]['rt']
sarcastic_rt = exp_data_clean[exp_data_clean['Exaggeration'] == 1]['rt']

print(f"\nLiteral (Exaggeration=0) 平均RT: {literal_rt.mean():.2f} ms (SD={literal_rt.std():.2f})")
print(f"Sarcastic (Exaggeration=1) 平均RT: {sarcastic_rt.mean():.2f} ms (SD={sarcastic_rt.std():.2f})")
print(f"差异: {sarcastic_rt.mean() - literal_rt.mean():.2f} ms")

# 独立样本t检验
t_stat, p_value = stats.ttest_ind(sarcastic_rt, literal_rt)
print(f"\n独立样本t检验:")
print(f"  t = {t_stat:.4f}")
print(f"  p = {p_value:.4f}")

# Cohen's d 效应量
pooled_std = np.sqrt((literal_rt.std()**2 + sarcastic_rt.std()**2) / 2)
cohens_d = (sarcastic_rt.mean() - literal_rt.mean()) / pooled_std
print(f"  Cohen's d = {cohens_d:.4f}")

# 2. 按Format分组的效果
print("\n2. 按Format分组的Exaggeration效果:")
for format_type in ['direct', 'indirect']:
    format_data = exp_data_clean[exp_data_clean['format'] == format_type]
    lit = format_data[format_data['Exaggeration'] == 0]['rt']
    sar = format_data[format_data['Exaggeration'] == 1]['rt']

    if len(lit) > 0 and len(sar) > 0:
        t, p = stats.ttest_ind(sar, lit)
        d = (sar.mean() - lit.mean()) / np.sqrt((lit.std()**2 + sar.std()**2) / 2)
        print(f"\n  {format_type.capitalize()} Format:")
        print(f"    Literal: {lit.mean():.2f} ms")
        print(f"    Sarcastic: {sar.mean():.2f} ms")
        print(f"    差异: {sar.mean() - lit.mean():.2f} ms")
        print(f"    t = {t:.4f}, p = {p:.4f}, d = {d:.4f}")

# 3. 双因素方差分析
print("\n3. 双因素方差分析 (2×2 ANOVA):")
from scipy.stats import f_oneway

# 为ANOVA准备数据
exp_data_clean['condition'] = exp_data_clean['Exaggeration'].astype(str) + '_' + exp_data_clean['format']
groups = [group['rt'].values for name, group in exp_data_clean.groupby('condition')]

if len(groups) == 4:
    f_stat, p_value_anova = f_oneway(*groups)
    print(f"  F = {f_stat:.4f}")
    print(f"  p = {p_value_anova:.4f}")

# 总结
print("\n" + "="*60)
print("===== EXAGGERATION 效应总结 =====")
print("="*60)

if p_value < 0.001:
    significance = "***极其显著***"
    conclusion = "Exaggeration有极其显著的效果"
elif p_value < 0.01:
    significance = "**非常显著**"
    conclusion = "Exaggeration有非常显著的效果"
elif p_value < 0.05:
    significance = "*显著*"
    conclusion = "Exaggeration有显著的效果"
else:
    significance = "不显著"
    conclusion = "Exaggeration没有显著效果"

print(f"\n主要发现:")
print(f"  - Literal条件平均阅读时间: {literal_rt.mean():.2f} ms")
print(f"  - Sarcastic条件平均阅读时间: {sarcastic_rt.mean():.2f} ms")
print(f"  - 阅读时间差异: {abs(sarcastic_rt.mean() - literal_rt.mean()):.2f} ms")
print(f"  - t值: {t_stat:.4f}")
print(f"  - p值: {p_value:.4f} {significance}")
print(f"  - 效应量 (Cohen's d): {cohens_d:.4f}")

print(f"\n结论: {conclusion} (p = {p_value:.4f})")

if cohens_d < 0.2:
    effect_size_interpretation = "极小"
elif cohens_d < 0.5:
    effect_size_interpretation = "小"
elif cohens_d < 0.8:
    effect_size_interpretation = "中等"
else:
    effect_size_interpretation = "大"

print(f"效应量解释: {effect_size_interpretation}效应")

print("\n分析完成!")
print(f"结果已保存到: descriptive_statistics.csv")

#!/usr/bin/env python3
"""
分析刺激材料中的Exaggeration变量编码
"""

import pandas as pd
import matplotlib.pyplot as plt

print("="*60)
print("刺激材料(Stimuli)中的Exaggeration分析")
print("="*60)

# 读取stimuli数据
stimuli = pd.read_csv('stimuli.csv')

print(f"\n数据概览:")
print(f"  总条目数: {len(stimuli)}")
print(f"  列数: {len(stimuli.columns)}")

# Exaggeration变量分析
print(f"\n" + "="*60)
print(f"Exaggeration变量编码分析")
print(f"="*60)

exag_counts = stimuli['Exaggeration'].value_counts().sort_index()
print(f"\nExaggeration编码分布:")
for val, count in exag_counts.items():
    print(f"  Exaggeration = {val}: {count} 个条目 ({count/len(stimuli)*100:.1f}%)")

# 按type和Exaggeration分组
print(f"\n按实验类型(type)和Exaggeration分组:")
type_exag = stimuli.groupby(['type', 'Exaggeration']).size().reset_index(name='count')
print(type_exag)

# 按format和Exaggeration分组
print(f"\n按言语形式(format)和Exaggeration分组:")
format_exag = stimuli.groupby(['format', 'Exaggeration']).size().reset_index(name='count')
print(format_exag)

# 查看Exaggeration与type的对应关系
print(f"\n按言语类型(type.1)和Exaggeration分组:")
type1_exag = stimuli.groupby(['type.1', 'Exaggeration']).size().reset_index(name='count')
print(type1_exag)

# 示例
print(f"\n" + "="*60)
print(f"示例说明")
print(f"="*60)

print(f"\nExaggeration = 0 (Literal/字面意思) 的示例:")
lit_example = stimuli[stimuli['Exaggeration'] == 0].iloc[0]
print(f"  Item: {lit_example['item_id']}")
print(f"  Type: {lit_example['type.1']}")
print(f"  Critical word: {lit_example['critical']}")
print(f"  Stimuli: {lit_example['stimuli'][:100]}...")

print(f"\nExaggeration = 1 (Sarcastic/讽刺/夸张) 的示例:")
sarc_example = stimuli[stimuli['Exaggeration'] == 1].iloc[0]
print(f"  Item: {sarc_example['item_id']}")
print(f"  Type: {sarc_example['type.1']}")
print(f"  Critical word: {sarc_example['critical']}")
print(f"  Stimuli: {sarc_example['stimuli'][:100]}...")

# 生成可视化
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

# 图1: Exaggeration总体分布
exag_counts.plot(kind='bar', ax=ax1, color=['#3498db', '#e74c3c'])
ax1.set_title('Exaggeration编码分布', fontsize=14, fontweight='bold')
ax1.set_xlabel('Exaggeration (0=Literal, 1=Sarcastic)', fontsize=12)
ax1.set_ylabel('条目数量', fontsize=12)
ax1.set_xticklabels(['Literal (0)', 'Sarcastic (1)'], rotation=0)
ax1.grid(axis='y', alpha=0.3)

# 图2: 按Format分组的Exaggeration分布
format_pivot = stimuli.pivot_table(
    values='item',
    index='format',
    columns='Exaggeration',
    aggfunc='count',
    fill_value=0
)
format_pivot.plot(kind='bar', ax=ax2, color=['#3498db', '#e74c3c'])
ax2.set_title('按Format分组的Exaggeration分布', fontsize=14, fontweight='bold')
ax2.set_xlabel('Format', fontsize=12)
ax2.set_ylabel('条目数量', fontsize=12)
ax2.set_xticklabels(['Direct', 'Indirect'], rotation=0)
ax2.legend(['Literal (0)', 'Sarcastic (1)'], title='Exaggeration')
ax2.grid(axis='y', alpha=0.3)

plt.tight_layout()
plt.savefig('exaggeration_distribution.png', dpi=300, bbox_inches='tight')
print(f"\n可视化图表已保存到: exaggeration_distribution.png")

# 总结
print(f"\n" + "="*60)
print(f"总结")
print(f"="*60)

print(f"""
根据stimuli.csv文件的分析:

1. **Exaggeration变量编码**:
   - Exaggeration = 0: Literal(字面意思)条件,共{exag_counts[0]}个条目
   - Exaggeration = 1: Sarcastic(讽刺/夸张)条件,共{exag_counts[1]}个条目

2. **实验设计**:
   - 这是一个2×2的实验设计
   - 因变量1: Exaggeration (Literal vs. Sarcastic)
   - 因变量2: Format (Direct vs. Indirect)

3. **分析Exaggeration效果**:
   要分析exaggeration是否有显著效果,需要比较:
   - Literal条件(Exaggeration=0)的阅读时间
   - Sarcastic条件(Exaggeration=1)的阅读时间

   **典型预期**:如果exaggeration有效果,讽刺/夸张条件的阅读时间
   应该显著不同于字面意思条件(通常会更长,因为需要更多的
   语用推理来理解说话人的真实意图)。

4. **数据文件说明**:
   - 当前的results_prod.csv和results_prod_sona.csv文件格式
     与标准的PennController自定进度阅读数据不匹配
   - 如果您有原始的PCIbex实验数据文件,请提供以便进行
     完整的统计分析
""")

print(f"\n分析完成!")

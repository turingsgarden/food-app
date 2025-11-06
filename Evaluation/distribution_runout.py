"""
simple distribution plots for avg_diff and avg_pct_diff
avg_diff point distribution and histogram
avg_pct_diff point distribution and histogram
"""
# import pandas as pd
# import matplotlib.pyplot as plt
# import seaborn as sns
# import numpy as np
# from scipy import stats
# import warnings
# warnings.filterwarnings('ignore')

# def plot_avg_differences_distribution():
#     # File path
#     input_file = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\Evaluation\avg_ingredient_comparison_optimized_700-800.xlsx"
    
#     # Read Excel file
#     df = pd.read_excel(input_file)
    
#     # Extract unique image_filename entries with corresponding avg_diff and avg_pct_diff
#     unique_avg_data = df.drop_duplicates(subset=['image_filename'])[['image_filename', 'avg_diff', 'avg_pct_diff']]
    
#     # Filter valid avg_diff and avg_pct_diff values (exclude NaN)
#     valid_avg_diff = unique_avg_data['avg_diff'].dropna()
#     valid_avg_pct_diff = unique_avg_data['avg_pct_diff'].dropna()
    
#     print(f"📊 Data Overview:")
#     print(f"Unique image files: {len(unique_avg_data)}")
#     print(f"Valid avg_diff data points: {len(valid_avg_diff)}")
#     print(f"Valid avg_pct_diff data points: {len(valid_avg_pct_diff)}")
    
#     # Plot style
#     plt.style.use('default')
#     sns.set_palette("husl")
    
#     # Create figure
#     fig, axes = plt.subplots(2, 2, figsize=(16, 12))
#     fig.suptitle('Distribution Analysis of Average Differences per Image', fontsize=16, fontweight='bold')
    
#     # === 1. Scatter plot for avg_diff ===
#     ax1 = axes[0, 0]
#     x_positions = np.arange(len(valid_avg_diff))
#     colors = ['red' if x > 0 else 'blue' for x in valid_avg_diff]
#     scatter1 = ax1.scatter(x_positions, valid_avg_diff, alpha=0.7, s=50, 
#                            c=colors, edgecolors='black', linewidth=0.5)
    
#     ax1.axhline(y=0, color='black', linestyle='-', alpha=0.8, linewidth=2, label='Zero Line')
#     ax1.axhline(y=valid_avg_diff.mean(), color='green', linestyle='--', alpha=0.8, linewidth=1.5, 
#                 label=f'Mean: {valid_avg_diff.mean():.2f}')
    
#     ax1.set_xlabel('Image Index')
#     ax1.set_ylabel('Average Difference (g/ml)')
#     ax1.set_title('A. Point Distribution of Average Differences\n(per image, Red = Overestimation, Blue = Underestimation)', 
#                   fontsize=12, fontweight='bold')
#     ax1.legend()
#     ax1.grid(True, alpha=0.3)
    
#     # === 2. Histogram for avg_diff ===
#     ax2 = axes[0, 1]
#     positive_diff = valid_avg_diff[valid_avg_diff > 0]
#     negative_diff = valid_avg_diff[valid_avg_diff < 0]
    
#     if len(positive_diff) > 0:
#         ax2.hist(positive_diff, bins=15, alpha=0.7, color='red', 
#                  edgecolor='darkred', density=True, label='Overestimation (+)')
#     if len(negative_diff) > 0:
#         ax2.hist(negative_diff, bins=15, alpha=0.7, color='blue', 
#                  edgecolor='darkblue', density=True, label='Underestimation (-)')
    
#     ax2.axvline(valid_avg_diff.mean(), color='green', linestyle='--', linewidth=2, 
#                 label=f'Mean: {valid_avg_diff.mean():.2f}')
#     ax2.axvline(0, color='black', linestyle='-', linewidth=1, alpha=0.5)
    
#     ax2.set_xlabel('Average Difference (g/ml)')
#     ax2.set_ylabel('Density')
#     ax2.set_title('B. Histogram of Average Differences\n(Overestimation vs Underestimation)', 
#                   fontsize=12, fontweight='bold')
#     ax2.legend()
#     ax2.grid(True, alpha=0.3)
    
#     # === 3. Scatter plot for avg_pct_diff ===
#     ax3 = axes[1, 0]
#     pct_threshold = 150  # Only display within ±150%
#     mask = np.abs(valid_avg_pct_diff) <= pct_threshold
#     filtered_avg_pct_diff = valid_avg_pct_diff[mask]
#     filtered_x_positions = np.arange(len(filtered_avg_pct_diff))
#     pct_colors = ['red' if x > 0 else 'blue' for x in filtered_avg_pct_diff]
    
#     scatter2 = ax3.scatter(filtered_x_positions, filtered_avg_pct_diff, alpha=0.7, s=50,
#                            c=pct_colors, edgecolors='black', linewidth=0.5)
    
#     ax3.axhline(y=0, color='black', linestyle='-', alpha=0.8, linewidth=2, label='Zero Line')
#     ax3.axhline(y=filtered_avg_pct_diff.mean(), color='green', linestyle='--', alpha=0.8, linewidth=1.5,
#                 label=f'Mean: {filtered_avg_pct_diff.mean():.2f}%')
    
#     ax3.set_xlabel('Image Index')
#     ax3.set_ylabel('Average Percentage Difference (%)')
#     ax3.set_title(f'C. Point Distribution of Average Percentage Differences\n(per image, Red = Overestimation, Blue = Underestimation, ±{pct_threshold}%)', 
#                   fontsize=12, fontweight='bold')
#     ax3.legend()
#     ax3.grid(True, alpha=0.3)
    
#     # === 4. Histogram for avg_pct_diff ===
#     ax4 = axes[1, 1]
#     pct_threshold_hist = 100
#     mask_hist = np.abs(valid_avg_pct_diff) <= pct_threshold_hist
#     filtered_avg_pct_diff_hist = valid_avg_pct_diff[mask_hist]
    
#     positive_pct = filtered_avg_pct_diff_hist[filtered_avg_pct_diff_hist > 0]
#     negative_pct = filtered_avg_pct_diff_hist[filtered_avg_pct_diff_hist < 0]
    
#     if len(positive_pct) > 0:
#         ax4.hist(positive_pct, bins=12, alpha=0.7, color='red', 
#                  edgecolor='darkred', density=True, label='Overestimation (+)')
#     if len(negative_pct) > 0:
#         ax4.hist(negative_pct, bins=12, alpha=0.7, color='blue', 
#                  edgecolor='darkblue', density=True, label='Underestimation (-)')
    
#     ax4.axvline(filtered_avg_pct_diff_hist.mean(), color='green', linestyle='--', linewidth=2,
#                 label=f'Mean: {filtered_avg_pct_diff_hist.mean():.2f}%')
#     ax4.axvline(0, color='black', linestyle='-', linewidth=1, alpha=0.5)
    
#     ax4.set_xlabel('Average Percentage Difference (%)')
#     ax4.set_ylabel('Density')
#     ax4.set_title(f'D. Histogram of Average Percentage Differences\n(Overestimation vs Underestimation, ±{pct_threshold_hist}%)', 
#                   fontsize=12, fontweight='bold')
#     ax4.legend()
#     ax4.grid(True, alpha=0.3)
    
#     plt.tight_layout()
    
#     # Save figure
#     output_image = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\Evaluation\detailed_average_differences_distribution.png"
#     plt.savefig(output_image, dpi=300, bbox_inches='tight', facecolor='white')
#     plt.show()
    
#     # === Descriptive statistics ===
#     print(f"\n📈 Average Differences (avg_diff) Summary:")
#     print(f"   Count: {len(valid_avg_diff)}")
#     print(f"   Mean: {valid_avg_diff.mean():.2f} g/ml")
#     print(f"   Median: {valid_avg_diff.median():.2f} g/ml")
#     print(f"   Std Dev: {valid_avg_diff.std():.2f} g/ml")
#     print(f"   Min: {valid_avg_diff.min():.2f} g/ml")
#     print(f"   Max: {valid_avg_diff.max():.2f} g/ml")
#     print(f"   25th percentile: {valid_avg_diff.quantile(0.25):.2f} g/ml")
#     print(f"   75th percentile: {valid_avg_diff.quantile(0.75):.2f} g/ml")
    
#     positive_count = len(valid_avg_diff[valid_avg_diff > 0])
#     negative_count = len(valid_avg_diff[valid_avg_diff < 0])
#     zero_count = len(valid_avg_diff[valid_avg_diff == 0])
    
#     print(f"   Overestimations (+): {positive_count} ({positive_count/len(valid_avg_diff)*100:.1f}%)")
#     print(f"   Underestimations (-): {negative_count} ({negative_count/len(valid_avg_diff)*100:.1f}%)")
#     print(f"   Exact matches (0): {zero_count} ({zero_count/len(valid_avg_diff)*100:.1f}%)")
    
#     print(f"\n📊 Average Percentage Differences (avg_pct_diff) Summary:")
#     print(f"   Count: {len(valid_avg_pct_diff)}")
#     print(f"   Mean: {valid_avg_pct_diff.mean():.2f}%")
#     print(f"   Median: {valid_avg_pct_diff.median():.2f}%")
#     print(f"   Std Dev: {valid_avg_pct_diff.std():.2f}%")
#     print(f"   Min: {valid_avg_pct_diff.min():.2f}%")
#     print(f"   Max: {valid_avg_pct_diff.max():.2f}%")
#     print(f"   25th percentile: {valid_avg_pct_diff.quantile(0.25):.2f}%")
#     print(f"   75th percentile: {valid_avg_pct_diff.quantile(0.75):.2f}%")
    
#     positive_pct_count = len(valid_avg_pct_diff[valid_avg_pct_diff > 0])
#     negative_pct_count = len(valid_avg_pct_diff[valid_avg_pct_diff < 0])
#     zero_pct_count = len(valid_avg_pct_diff[valid_avg_pct_diff == 0])
    
#     print(f"   Overestimations (+): {positive_pct_count} ({positive_pct_count/len(valid_avg_pct_diff)*100:.1f}%)")
#     print(f"   Underestimations (-): {negative_pct_count} ({negative_pct_count/len(valid_avg_pct_diff)*100:.1f}%)")
#     print(f"   Exact matches (0): {zero_pct_count} ({zero_pct_count/len(valid_avg_pct_diff)*100:.1f}%)")
    
#     # === Range coverage ===
#     print(f"\n🎯 Average Difference Coverage:")
#     diff_ranges = [(5, "±5 g/ml"), (10, "±10 g/ml"), (20, "±20 g/ml"), (30, "±30 g/ml")]
#     for threshold, label in diff_ranges:
#         within_range = len(valid_avg_diff[np.abs(valid_avg_diff) <= threshold]) / len(valid_avg_diff) * 100
#         print(f"   Within {label}: {within_range:.1f}%")
    
#     print(f"\n🎯 Average Percentage Difference Coverage:")
#     pct_ranges = [(10, "±10%"), (20, "±20%"), (50, "±50%"), (100, "±100%")]
#     for threshold, label in pct_ranges:
#         within_range = len(valid_avg_pct_diff[np.abs(valid_avg_pct_diff) <= threshold]) / len(valid_avg_pct_diff) * 100
#         print(f"   Within {label}: {within_range:.1f}%")
    
#     print(f"\n💾 Figure saved to: {output_image}")

# if __name__ == "__main__":
#     plot_avg_differences_distribution()

#==================================================================================================================================
"""
Complex distribution plots for avg_diff and avg_pct_diff
avg_diff point distribution and histogram
avg_pct_diff point distribution and histogram
Boxplot Comparison
Cumulative Distribution Function (CDF)
Correlation Scatter Plot
Error Direction Pie Chart
Performance Category Bar Chart
Statistical Summary Table
2D Distribution Heatmap
Performance Distribution by Error Magnitude
"""

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
from scipy import stats
import warnings
warnings.filterwarnings('ignore')

def plot_comprehensive_avg_differences_analysis():
    # File paths
    input_file = "Evaluation/Nutrition5k_295/Nutritio5k_295.xlsx"
    # Read Excel file
    df = pd.read_excel(input_file)
    
    # Extract unique image_filename with corresponding avg_diff and avg_pct_diff
    unique_avg_data = df.drop_duplicates(subset=['image_filename'])[['image_filename', 'avg_diff', 'avg_pct_diff']]
    
    # Filter valid avg_diff and avg_pct_diff data (exclude null values)
    valid_avg_diff = unique_avg_data['avg_diff'].dropna()
    valid_avg_pct_diff = unique_avg_data['avg_pct_diff'].dropna()
    
    print(f"📊 Data Statistics:")
    print(f"Unique image count: {len(unique_avg_data)}")
    print(f"Valid avg_diff data points: {len(valid_avg_diff)}")
    print(f"Valid avg_pct_diff data points: {len(valid_avg_pct_diff)}")
    
    # Set graphic style
    plt.style.use('default')
    sns.set_palette("husl")
    
    # Create larger figure - includes more analysis charts
    fig = plt.figure(figsize=(24, 20))
    fig.suptitle('Comprehensive Analysis of Average Differences per Image', fontsize=18, fontweight='bold')
    
    # Define grid layout
    gs = fig.add_gridspec(4, 4)
    
    # 1. avg_diff point distribution (with positive/negative direction)
    ax1 = fig.add_subplot(gs[0, 0])
    x_positions = np.arange(len(valid_avg_diff))
    
    colors = ['red' if x > 0 else 'blue' for x in valid_avg_diff]
    sizes = [50 + abs(x)*2 for x in valid_avg_diff]  # Size reflects difference magnitude
    
    scatter1 = ax1.scatter(x_positions, valid_avg_diff, alpha=0.7, s=sizes, 
                          c=colors, edgecolors='black', linewidth=0.5)
    
    ax1.axhline(y=0, color='black', linestyle='-', alpha=0.8, linewidth=2, label='Zero Line')
    ax1.axhline(y=valid_avg_diff.mean(), color='green', linestyle='--', alpha=0.8, linewidth=1.5, 
               label=f'Mean: {valid_avg_diff.mean():.2f}')
    
    ax1.set_xlabel('Image Index')
    ax1.set_ylabel('Average Difference (g/ml)')
    ax1.set_title('A. Point Distribution of Average Differences\n(Size indicates magnitude)', 
                 fontsize=12, fontweight='bold')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # 2. avg_diff histogram (showing positive/negative distribution)
    ax2 = fig.add_subplot(gs[0, 1])
    positive_diff = valid_avg_diff[valid_avg_diff > 0]
    negative_diff = valid_avg_diff[valid_avg_diff < 0]
    
    if len(positive_diff) > 0:
        ax2.hist(positive_diff, bins=15, alpha=0.7, color='red', 
                edgecolor='darkred', density=True, label='Overestimation (+)')
    if len(negative_diff) > 0:
        ax2.hist(negative_diff, bins=15, alpha=0.7, color='blue', 
                edgecolor='darkblue', density=True, label='Underestimation (-)')
    
    ax2.axvline(valid_avg_diff.mean(), color='green', linestyle='--', linewidth=2, 
               label=f'Mean: {valid_avg_diff.mean():.2f}')
    ax2.axvline(0, color='black', linestyle='-', linewidth=1, alpha=0.5)
    
    ax2.set_xlabel('Average Difference (g/ml)')
    ax2.set_ylabel('Density')
    ax2.set_title('B. Histogram of Average Differences', 
                 fontsize=12, fontweight='bold')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    # 3. avg_pct_diff point distribution
    ax3 = fig.add_subplot(gs[0, 2])
    pct_threshold = 150
    mask = np.abs(valid_avg_pct_diff) <= pct_threshold
    filtered_avg_pct_diff = valid_avg_pct_diff[mask]
    filtered_x_positions = np.arange(len(filtered_avg_pct_diff))
    
    pct_colors = ['red' if x > 0 else 'blue' for x in filtered_avg_pct_diff]
    pct_sizes = [50 + abs(x)/5 for x in filtered_avg_pct_diff]
    
    scatter2 = ax3.scatter(filtered_x_positions, filtered_avg_pct_diff, alpha=0.7, s=pct_sizes,
                          c=pct_colors, edgecolors='black', linewidth=0.5)
    
    ax3.axhline(y=0, color='black', linestyle='-', alpha=0.8, linewidth=2, label='Zero Line')
    ax3.axhline(y=filtered_avg_pct_diff.mean(), color='green', linestyle='--', alpha=0.8, linewidth=1.5,
               label=f'Mean: {filtered_avg_pct_diff.mean():.2f}%')
    
    ax3.set_xlabel('Image Index')
    ax3.set_ylabel('Average Percentage Difference (%)')
    ax3.set_title(f'C. Point Distribution of Average % Differences\n(±{pct_threshold}%)', 
                 fontsize=12, fontweight='bold')
    ax3.legend()
    ax3.grid(True, alpha=0.3)
    
    # 4. avg_pct_diff histogram
    ax4 = fig.add_subplot(gs[0, 3])
    pct_threshold_hist = 100
    mask_hist = np.abs(valid_avg_pct_diff) <= pct_threshold_hist
    filtered_avg_pct_diff_hist = valid_avg_pct_diff[mask_hist]
    
    positive_pct = filtered_avg_pct_diff_hist[filtered_avg_pct_diff_hist > 0]
    negative_pct = filtered_avg_pct_diff_hist[filtered_avg_pct_diff_hist < 0]
    
    if len(positive_pct) > 0:
        ax4.hist(positive_pct, bins=12, alpha=0.7, color='red', 
                edgecolor='darkred', density=True, label='Overestimation (+)')
    if len(negative_pct) > 0:
        ax4.hist(negative_pct, bins=12, alpha=0.7, color='blue', 
                edgecolor='darkblue', density=True, label='Underestimation (-)')
    
    ax4.axvline(filtered_avg_pct_diff_hist.mean(), color='green', linestyle='--', linewidth=2,
               label=f'Mean: {filtered_avg_pct_diff_hist.mean():.2f}%')
    ax4.axvline(0, color='black', linestyle='-', linewidth=1, alpha=0.5)
    
    ax4.set_xlabel('Average Percentage Difference (%)')
    ax4.set_ylabel('Density')
    ax4.set_title(f'D. Histogram of Average % Differences\n(±{pct_threshold_hist}%)', 
                 fontsize=12, fontweight='bold')
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    
    # 5. Box plot comparison
    ax5 = fig.add_subplot(gs[1, 0])
    data_to_plot = [valid_avg_diff, valid_avg_pct_diff[np.abs(valid_avg_pct_diff) <= 200]]
    box_plot = ax5.boxplot(data_to_plot, patch_artist=True, 
                          labels=['Absolute Diff (g/ml)', 'Percentage Diff (%)'])
    
    colors = ['lightblue', 'lightgreen']
    for patch, color in zip(box_plot['boxes'], colors):
        patch.set_facecolor(color)
        patch.set_alpha(0.7)
    
    ax5.set_ylabel('Difference Value')
    ax5.set_title('E. Box Plot Comparison\n(Distribution Ranges)', 
                 fontsize=12, fontweight='bold')
    ax5.grid(True, alpha=0.3)
    
    # 6. Cumulative distribution function plot
    ax6 = fig.add_subplot(gs[1, 1])
    sorted_diff = np.sort(valid_avg_diff)
    cdf_diff = np.arange(1, len(sorted_diff) + 1) / len(sorted_diff)
    
    sorted_pct = np.sort(valid_avg_pct_diff[np.abs(valid_avg_pct_diff) <= 200])
    cdf_pct = np.arange(1, len(sorted_pct) + 1) / len(sorted_pct)
    
    ax6.plot(sorted_diff, cdf_diff, linewidth=3, color='blue', label='Absolute Differences')
    ax6.plot(sorted_pct/10, cdf_pct, linewidth=3, color='red', label='Percentage Differences (/10)')
    
    # Add key percentile lines
    for percentile in [25, 50, 75, 90]:
        idx = int(len(sorted_diff) * percentile / 100)
        if idx < len(sorted_diff):
            ax6.axvline(sorted_diff[idx], color='blue', linestyle=':', alpha=0.5)
            ax6.text(sorted_diff[idx], 0.5, f'{percentile}%', rotation=90, fontsize=8)
    
    ax6.set_xlabel('Difference Value')
    ax6.set_ylabel('Cumulative Probability')
    ax6.set_title('F. Cumulative Distribution Function', 
                 fontsize=12, fontweight='bold')
    ax6.legend()
    ax6.grid(True, alpha=0.3)
    
    # 7. Scatter plot: Absolute differences vs Percentage differences
    ax7 = fig.add_subplot(gs[1, 2])
    common_indices = valid_avg_diff.index.intersection(valid_avg_pct_diff.index)
    avg_diff_common = valid_avg_diff.loc[common_indices]
    avg_pct_common = valid_avg_pct_diff.loc[common_indices]
    
    # Filter extreme values
    mask_scatter = (np.abs(avg_diff_common) <= 50) & (np.abs(avg_pct_common) <= 200)
    scatter3 = ax7.scatter(avg_diff_common[mask_scatter], avg_pct_common[mask_scatter], 
                          alpha=0.6, s=60, c=avg_diff_common[mask_scatter], cmap='coolwarm')
    
    ax7.axhline(y=0, color='red', linestyle='-', alpha=0.5, linewidth=1)
    ax7.axvline(x=0, color='red', linestyle='-', alpha=0.5, linewidth=1)
    ax7.set_xlabel('Average Absolute Difference (g/ml)')
    ax7.set_ylabel('Average Percentage Difference (%)')
    ax7.set_title('G. Correlation: Absolute vs Percentage Differences', 
                 fontsize=12, fontweight='bold')
    ax7.grid(True, alpha=0.3)
    
    # Add color bar
    cbar3 = plt.colorbar(scatter3, ax=ax7)
    cbar3.set_label('Absolute Difference (g/ml)', rotation=270, labelpad=15)
    
    # 8. Error direction analysis pie chart
    ax8 = fig.add_subplot(gs[1, 3])
    positive_count = len(valid_avg_diff[valid_avg_diff > 0])
    negative_count = len(valid_avg_diff[valid_avg_diff < 0])
    zero_count = len(valid_avg_diff[valid_avg_diff == 0])
    
    sizes = [positive_count, negative_count, zero_count]
    labels = [f'Overestimation\n({positive_count})', 
              f'Underestimation\n({negative_count})', 
              f'Accurate\n({zero_count})']
    colors = ['red', 'blue', 'green']
    
    wedges, texts, autotexts = ax8.pie(sizes, labels=labels, colors=colors, autopct='%1.1f%%',
                                      startangle=90)
    for autotext in autotexts:
        autotext.set_color('white')
        autotext.set_fontweight('bold')
    
    ax8.set_title('H. Prediction Direction Analysis', fontsize=12, fontweight='bold')
    
    # 9. Performance classification bar chart
    ax9 = fig.add_subplot(gs[2, 0])
    performance_categories = {
        'Excellent (±5g/10%)': len(valid_avg_diff[(np.abs(valid_avg_diff) <= 5) & (np.abs(valid_avg_pct_diff) <= 10)]),
        'Good (±10g/20%)': len(valid_avg_diff[(np.abs(valid_avg_diff) <= 10) & (np.abs(valid_avg_pct_diff) <= 20)]),
        'Fair (±20g/50%)': len(valid_avg_diff[(np.abs(valid_avg_diff) <= 20) & (np.abs(valid_avg_pct_diff) <= 50)]),
        'Poor (>20g/50%)': len(valid_avg_diff[(np.abs(valid_avg_diff) > 20) | (np.abs(valid_avg_pct_diff) > 50)])
    }
    
    categories = list(performance_categories.keys())
    counts = list(performance_categories.values())
    colors = ['green', 'lightgreen', 'orange', 'red']
    
    bars = ax9.bar(categories, counts, color=colors, alpha=0.7, edgecolor='black')
    ax9.set_ylabel('Number of Images')
    ax9.set_title('I. Performance Classification', fontsize=12, fontweight='bold')
    ax9.tick_params(axis='x', rotation=45)
    
    # Add values on bars
    for bar, count in zip(bars, counts):
        height = bar.get_height()
        ax9.text(bar.get_x() + bar.get_width()/2., height + 0.1,
                f'{count}\n({count/len(valid_avg_diff)*100:.1f}%)',
                ha='center', va='bottom', fontsize=9)
    
    # 10. REPLACED: Performance trend by magnitude (替代时间序列分析)
    ax10 = fig.add_subplot(gs[2, 1])
    
    # Sort by absolute difference magnitude
    sorted_by_magnitude_indices = np.argsort(np.abs(valid_avg_diff))
    sorted_by_magnitude_diff = valid_avg_diff.iloc[sorted_by_magnitude_indices]
    
    # Create bins for performance analysis
    magnitude_bins = [0, 5, 10, 20, 50, float('inf')]
    bin_labels = ['0-5g', '5-10g', '10-20g', '20-50g', '50g+']
    bin_counts = []
    bin_means = []
    
    for i in range(len(magnitude_bins)-1):
        lower = magnitude_bins[i]
        upper = magnitude_bins[i+1]
        if upper == float('inf'):
            mask = np.abs(valid_avg_diff) >= lower
        else:
            mask = (np.abs(valid_avg_diff) >= lower) & (np.abs(valid_avg_diff) < upper)
        
        bin_data = valid_avg_diff[mask]
        bin_counts.append(len(bin_data))
        bin_means.append(bin_data.mean() if len(bin_data) > 0 else 0)
    
    # Plot performance by magnitude
    x_pos = range(len(bin_labels))
    bars1 = ax10.bar(x_pos, bin_counts, alpha=0.7, color='lightblue', 
                    edgecolor='navy', label='Number of Images')
    
    ax10.set_xlabel('Absolute Difference Magnitude (g/ml)')
    ax10.set_ylabel('Number of Images', color='blue')
    ax10.set_title('J. Performance Distribution by Error Magnitude', 
                  fontsize=12, fontweight='bold')
    ax10.set_xticks(x_pos)
    ax10.set_xticklabels(bin_labels)
    
    # Add second y-axis for mean differences
    ax10_secondary = ax10.twinx()
    ax10_secondary.plot(x_pos, bin_means, 'ro-', linewidth=2, markersize=8, 
                       label='Mean Difference')
    ax10_secondary.set_ylabel('Mean Difference (g/ml)', color='red')
    ax10_secondary.tick_params(axis='y', labelcolor='red')
    
    # Add count labels on bars
    for i, count in enumerate(bin_counts):
        ax10.text(i, count + max(bin_counts)*0.01, str(count), 
                 ha='center', va='bottom', fontweight='bold')
    
    ax10.grid(True, alpha=0.3)
    
    # 11. Statistical information table
    ax11 = fig.add_subplot(gs[2, 2:])
    ax11.axis('off')
    
    # Prepare detailed statistical information
    stats_data = [
        ['Metric', 'Absolute Diff', 'Percentage Diff'],
        ['Count', len(valid_avg_diff), len(valid_avg_pct_diff)],
        ['Mean', f'{valid_avg_diff.mean():.2f} g/ml', f'{valid_avg_pct_diff.mean():.2f}%'],
        ['Median', f'{valid_avg_diff.median():.2f} g/ml', f'{valid_avg_pct_diff.median():.2f}%'],
        ['Std Dev', f'{valid_avg_diff.std():.2f} g/ml', f'{valid_avg_pct_diff.std():.2f}%'],
        ['Min', f'{valid_avg_diff.min():.2f} g/ml', f'{valid_avg_pct_diff.min():.2f}%'],
        ['Max', f'{valid_avg_diff.max():.2f} g/ml', f'{valid_avg_pct_diff.max():.2f}%'],
        ['Q1 (25%)', f'{valid_avg_diff.quantile(0.25):.2f} g/ml', f'{valid_avg_pct_diff.quantile(0.25):.2f}%'],
        ['Q3 (75%)', f'{valid_avg_diff.quantile(0.75):.2f} g/ml', f'{valid_avg_pct_diff.quantile(0.75):.2f}%'],
        ['Overestimation', f'{positive_count} ({positive_count/len(valid_avg_diff)*100:.1f}%)', 
         f'{len(valid_avg_pct_diff[valid_avg_pct_diff > 0])} ({len(valid_avg_pct_diff[valid_avg_pct_diff > 0])/len(valid_avg_pct_diff)*100:.1f}%)'],
        ['Underestimation', f'{negative_count} ({negative_count/len(valid_avg_diff)*100:.1f}%)', 
         f'{len(valid_avg_pct_diff[valid_avg_pct_diff < 0])} ({len(valid_avg_pct_diff[valid_avg_pct_diff < 0])/len(valid_avg_pct_diff)*100:.1f}%)'],
    ]
    
    table = ax11.table(cellText=stats_data, 
                      cellLoc='center', 
                      loc='center',
                      bbox=[0, 0, 1, 1])
    table.auto_set_font_size(False)
    table.set_fontsize(8)
    table.scale(1, 2)
    ax11.set_title('K. Comprehensive Statistical Summary', fontsize=12, fontweight='bold', pad=20)
    
    # 12. Error distribution heatmap
    ax12 = fig.add_subplot(gs[3, :2])
    # Create 2D histogram
    x = valid_avg_diff
    y = valid_avg_pct_diff[np.abs(valid_avg_pct_diff) <= 200]
    
    # Ensure consistent length
    min_len = min(len(x), len(y))
    x_trimmed = x.iloc[:min_len]
    y_trimmed = y.iloc[:min_len]
    
    heatmap = ax12.hist2d(x_trimmed, y_trimmed, bins=20, cmap='YlOrRd')
    ax12.axhline(y=0, color='white', linestyle='-', alpha=0.5)
    ax12.axvline(x=0, color='white', linestyle='-', alpha=0.5)
    ax12.set_xlabel('Average Absolute Difference (g/ml)')
    ax12.set_ylabel('Average Percentage Difference (%)')
    ax12.set_title('L. 2D Distribution Heatmap\n(High density areas)', 
                  fontsize=12, fontweight='bold')
    
    plt.colorbar(heatmap[3], ax=ax12, label='Number of Images')
    
    # 13. Residual Q-Q plot (testing normality)
    ax13 = fig.add_subplot(gs[3, 2])
    stats.probplot(valid_avg_diff, dist="norm", plot=ax13)
    ax13.set_title('M. Q-Q Plot: Normality Test\n(Absolute Differences)', 
                  fontsize=12, fontweight='bold')
    
    # 14. Percentage difference Q-Q plot
    ax14 = fig.add_subplot(gs[3, 3])
    filtered_pct_for_qq = valid_avg_pct_diff[np.abs(valid_avg_pct_diff) <= 100]
    stats.probplot(filtered_pct_for_qq, dist="norm", plot=ax14)
    ax14.set_title('N. Q-Q Plot: Normality Test\n(Percentage Differences)', 
                  fontsize=12, fontweight='bold')
    
    plt.tight_layout()
    
    # Save image
    output_image = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\Evaluation\comprehensive_avg_differences_analysis.png"
    plt.savefig(output_image, dpi=300, bbox_inches='tight', facecolor='white')
    plt.show()
    
    # Print additional statistical information
    print_comprehensive_statistics(valid_avg_diff, valid_avg_pct_diff)
    
    print(f"\n💾 Comprehensive analysis chart saved to: {output_image}")

def print_comprehensive_statistics(valid_avg_diff, valid_avg_pct_diff):
    """Print comprehensive statistical information"""
    print(f"\n📈 COMPREHENSIVE STATISTICAL ANALYSIS")
    print("="*50)
    
    # Basic statistics
    print(f"\n📊 Basic Statistics:")
    print(f"   Total Images Analyzed: {len(valid_avg_diff)}")
    print(f"   Mean Absolute Difference: {valid_avg_diff.mean():.2f} ± {valid_avg_diff.std():.2f} g/ml")
    print(f"   Mean Percentage Difference: {valid_avg_pct_diff.mean():.2f} ± {valid_avg_pct_diff.std():.2f}%")
    
    # Direction analysis
    positive_diff = len(valid_avg_diff[valid_avg_diff > 0])
    negative_diff = len(valid_avg_diff[valid_avg_diff < 0])
    print(f"\n🎯 Prediction Direction:")
    print(f"   Overestimation: {positive_diff} images ({positive_diff/len(valid_avg_diff)*100:.1f}%)")
    print(f"   Underestimation: {negative_diff} images ({negative_diff/len(valid_avg_diff)*100:.1f}%)")
    print(f"   Net Bias: {(positive_diff - negative_diff)/len(valid_avg_diff)*100:+.1f}%")
    
    # Performance classification
    print(f"\n📋 Performance Classification:")
    thresholds = [
        (5, 10, "Excellent"),
        (10, 20, "Good"), 
        (20, 50, "Fair"),
        (float('inf'), float('inf'), "Poor")
    ]
    
    for abs_thresh, pct_thresh, category in thresholds:
        if abs_thresh == float('inf'):
            count = len(valid_avg_diff[(np.abs(valid_avg_diff) > 20) | (np.abs(valid_avg_pct_diff) > 50)])
        else:
            count = len(valid_avg_diff[(np.abs(valid_avg_diff) <= abs_thresh) & (np.abs(valid_avg_pct_diff) <= pct_thresh)])
        print(f"   {category}: {count} images ({count/len(valid_avg_diff)*100:.1f}%)")
    
    # Distribution range analysis
    print(f"\n📏 Distribution Ranges (Absolute Differences):")
    for threshold in [5, 10, 15, 20, 30]:
        within = len(valid_avg_diff[np.abs(valid_avg_diff) <= threshold])
        print(f"   ±{threshold}g: {within} images ({within/len(valid_avg_diff)*100:.1f}%)")
    
    print(f"\n📏 Distribution Ranges (Percentage Differences):")
    for threshold in [10, 20, 30, 50, 100]:
        within = len(valid_avg_pct_diff[np.abs(valid_avg_pct_diff) <= threshold])
        print(f"   ±{threshold}%: {within} images ({within/len(valid_avg_pct_diff)*100:.1f}%)")

if __name__ == "__main__":
    plot_comprehensive_avg_differences_analysis()








#======================================================================================================================
"""Single Images"""


# import pandas as pd
# import matplotlib.pyplot as plt
# import seaborn as sns
# import numpy as np
# from scipy import stats
# import warnings
# warnings.filterwarnings('ignore')

# def plot_individual_avg_differences_analysis():
#     # File paths
#     input_file = "Evaluation/Nutritio5k_296/Nutritio5k_295.xlsx"     
    
#     # Read Excel file
#     df = pd.read_excel(input_file)
    
#     # Extract unique image_filename with corresponding avg_diff and avg_pct_diff
#     unique_avg_data = df.drop_duplicates(subset=['image_filename'])[['image_filename', 'avg_diff', 'avg_pct_diff']]
    
#     # Filter valid avg_diff and avg_pct_diff data (exclude null values)
#     valid_avg_diff = unique_avg_data['avg_diff'].dropna()
#     valid_avg_pct_diff = unique_avg_data['avg_pct_diff'].dropna()
    
#     print(f"📊 Data Statistics:")
#     print(f"Unique image count: {len(unique_avg_data)}")
#     print(f"Valid avg_diff data points: {len(valid_avg_diff)}")
#     print(f"Valid avg_pct_diff data points: {len(valid_avg_pct_diff)}")
    
#     # Set graphic style
#     plt.style.use('default')
#     sns.set_palette("husl")
    
#     # 1. avg_diff point distribution
#     plt.figure(figsize=(12, 8))
#     x_positions = np.arange(len(valid_avg_diff))
    
#     colors = ['red' if x > 0 else 'blue' for x in valid_avg_diff]
#     sizes = [50 + abs(x)*2 for x in valid_avg_diff]  # Size reflects difference magnitude
    
#     scatter1 = plt.scatter(x_positions, valid_avg_diff, alpha=0.7, s=sizes, 
#                           c=colors, edgecolors='black', linewidth=0.5)
    
#     plt.axhline(y=0, color='black', linestyle='-', alpha=0.8, linewidth=2, label='Zero Line')
#     plt.axhline(y=valid_avg_diff.mean(), color='green', linestyle='--', alpha=0.8, linewidth=1.5, 
#                label=f'Mean: {valid_avg_diff.mean():.2f}')
    
#     plt.xlabel('Image Index')
#     plt.ylabel('Average Difference (g/ml)')
#     plt.title('Point Distribution of Average Differences\n(Red=Overestimation, Blue=Underestimation, Size indicates magnitude)', 
#              fontsize=14, fontweight='bold')
#     plt.legend()
#     plt.grid(True, alpha=0.3)
    
#     # Add statistics text box
#     stats_text = f'Total Images: {len(valid_avg_diff)}\nMean: {valid_avg_diff.mean():.2f} g/ml\nStd: {valid_avg_diff.std():.2f} g/ml\nMin: {valid_avg_diff.min():.2f} g/ml\nMax: {valid_avg_diff.max():.2f} g/ml'
#     plt.text(0.02, 0.98, stats_text, transform=plt.gca().transAxes, verticalalignment='top',
#              bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8), fontsize=10)
    
#     plt.tight_layout()
#     plt.savefig(r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\Evaluation\avg_diff_point_distribution.png", 
#                 dpi=300, bbox_inches='tight', facecolor='white')
#     plt.show()

#     # 2. avg_diff histogram
#     plt.figure(figsize=(12, 8))
#     positive_diff = valid_avg_diff[valid_avg_diff > 0]
#     negative_diff = valid_avg_diff[valid_avg_diff < 0]
    
#     if len(positive_diff) > 0:
#         plt.hist(positive_diff, bins=15, alpha=0.7, color='red', 
#                 edgecolor='darkred', density=True, label='Overestimation (+)')
#     if len(negative_diff) > 0:
#         plt.hist(negative_diff, bins=15, alpha=0.7, color='blue', 
#                 edgecolor='darkblue', density=True, label='Underestimation (-)')
    
#     plt.axvline(valid_avg_diff.mean(), color='green', linestyle='--', linewidth=2, 
#                label=f'Mean: {valid_avg_diff.mean():.2f}')
#     plt.axvline(valid_avg_diff.median(), color='orange', linestyle='--', linewidth=2, 
#                label=f'Median: {valid_avg_diff.median():.2f}')
#     plt.axvline(0, color='black', linestyle='-', linewidth=1, alpha=0.5)
    
#     plt.xlabel('Average Difference (g/ml)')
#     plt.ylabel('Density')
#     plt.title('Histogram of Average Differences\n(Showing Overestimation vs Underestimation)', 
#              fontsize=14, fontweight='bold')
#     plt.legend()
#     plt.grid(True, alpha=0.3)
    
#     # Add direction statistics
#     positive_count = len(positive_diff)
#     negative_count = len(negative_diff)
#     zero_count = len(valid_avg_diff[valid_avg_diff == 0])
#     direction_text = f'Overestimation: {positive_count} ({positive_count/len(valid_avg_diff)*100:.1f}%)\nUnderestimation: {negative_count} ({negative_count/len(valid_avg_diff)*100:.1f}%)\nAccurate: {zero_count} ({zero_count/len(valid_avg_diff)*100:.1f}%)'
#     plt.text(0.02, 0.98, direction_text, transform=plt.gca().transAxes, verticalalignment='top',
#              bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.8), fontsize=10)
    
#     plt.tight_layout()
#     plt.savefig(r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\Evaluation\avg_diff_histogram.png", 
#                 dpi=300, bbox_inches='tight', facecolor='white')
#     plt.show()
    
#     # 3. avg_pct_diff point distribution
#     plt.figure(figsize=(12, 8))
#     pct_threshold = 150
#     mask = np.abs(valid_avg_pct_diff) <= pct_threshold
#     filtered_avg_pct_diff = valid_avg_pct_diff[mask]
#     filtered_x_positions = np.arange(len(filtered_avg_pct_diff))
    
#     pct_colors = ['red' if x > 0 else 'blue' for x in filtered_avg_pct_diff]
#     pct_sizes = [50 + abs(x)/5 for x in filtered_avg_pct_diff]
    
#     scatter2 = plt.scatter(filtered_x_positions, filtered_avg_pct_diff, alpha=0.7, s=pct_sizes,
#                           c=pct_colors, edgecolors='black', linewidth=0.5)
    
#     plt.axhline(y=0, color='black', linestyle='-', alpha=0.8, linewidth=2, label='Zero Line')
#     plt.axhline(y=filtered_avg_pct_diff.mean(), color='green', linestyle='--', alpha=0.8, linewidth=1.5,
#                label=f'Mean: {filtered_avg_pct_diff.mean():.2f}%')
    
#     plt.xlabel('Image Index')
#     plt.ylabel('Average Percentage Difference (%)')
#     plt.title(f'Point Distribution of Average Percentage Differences\n(Red=Overestimation, Blue=Underestimation, Showing ±{pct_threshold}%)', 
#              fontsize=14, fontweight='bold')
#     plt.legend()
#     plt.grid(True, alpha=0.3)
    
#     # Add statistics text box
#     pct_stats_text = f'Total Images: {len(filtered_avg_pct_diff)}\nMean: {filtered_avg_pct_diff.mean():.2f}%\nStd: {filtered_avg_pct_diff.std():.2f}%\nMin: {filtered_avg_pct_diff.min():.2f}%\nMax: {filtered_avg_pct_diff.max():.2f}%'
#     plt.text(0.02, 0.98, pct_stats_text, transform=plt.gca().transAxes, verticalalignment='top',
#              bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8), fontsize=10)
    
#     plt.tight_layout()
#     plt.savefig(r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\Evaluation\avg_pct_diff_point_distribution.png", 
#                 dpi=300, bbox_inches='tight', facecolor='white')
#     plt.show()
    
#     # 4. avg_pct_diff histogram
#     plt.figure(figsize=(12, 8))
#     pct_threshold_hist = 100
#     mask_hist = np.abs(valid_avg_pct_diff) <= pct_threshold_hist
#     filtered_avg_pct_diff_hist = valid_avg_pct_diff[mask_hist]
    
#     positive_pct = filtered_avg_pct_diff_hist[filtered_avg_pct_diff_hist > 0]
#     negative_pct = filtered_avg_pct_diff_hist[filtered_avg_pct_diff_hist < 0]
    
#     if len(positive_pct) > 0:
#         plt.hist(positive_pct, bins=12, alpha=0.7, color='red', 
#                 edgecolor='darkred', density=True, label='Overestimation (+)')
#     if len(negative_pct) > 0:
#         plt.hist(negative_pct, bins=12, alpha=0.7, color='blue', 
#                 edgecolor='darkblue', density=True, label='Underestimation (-)')
    
#     plt.axvline(filtered_avg_pct_diff_hist.mean(), color='green', linestyle='--', linewidth=2,
#                label=f'Mean: {filtered_avg_pct_diff_hist.mean():.2f}%')
#     plt.axvline(filtered_avg_pct_diff_hist.median(), color='orange', linestyle='--', linewidth=2,
#                label=f'Median: {filtered_avg_pct_diff_hist.median():.2f}%')
#     plt.axvline(0, color='black', linestyle='-', linewidth=1, alpha=0.5)
    
#     plt.xlabel('Average Percentage Difference (%)')
#     plt.ylabel('Density')
#     plt.title(f'Histogram of Average Percentage Differences\n(Showing Overestimation vs Underestimation, ±{pct_threshold_hist}%)', 
#              fontsize=14, fontweight='bold')
#     plt.legend()
#     plt.grid(True, alpha=0.3)
    
#     # Add direction statistics
#     positive_pct_count = len(positive_pct)
#     negative_pct_count = len(negative_pct)
#     zero_pct_count = len(filtered_avg_pct_diff_hist[filtered_avg_pct_diff_hist == 0])
#     pct_direction_text = f'Overestimation: {positive_pct_count} ({positive_pct_count/len(filtered_avg_pct_diff_hist)*100:.1f}%)\nUnderestimation: {negative_pct_count} ({negative_pct_count/len(filtered_avg_pct_diff_hist)*100:.1f}%)\nAccurate: {zero_pct_count} ({zero_pct_count/len(filtered_avg_pct_diff_hist)*100:.1f}%)'
#     plt.text(0.02, 0.98, pct_direction_text, transform=plt.gca().transAxes, verticalalignment='top',
#              bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.8), fontsize=10)
    
#     plt.tight_layout()
#     plt.savefig(r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\Evaluation\avg_pct_diff_histogram.png", 
#                 dpi=300, bbox_inches='tight', facecolor='white')
#     plt.show()
    
#     # 5. Statistical table
#     plt.figure(figsize=(16, 10))
#     plt.axis('off')
    
#     # Prepare detailed statistical information
#     positive_count = len(valid_avg_diff[valid_avg_diff > 0])
#     negative_count = len(valid_avg_diff[valid_avg_diff < 0])
#     zero_count = len(valid_avg_diff[valid_avg_diff == 0])
    
#     positive_pct_count_all = len(valid_avg_pct_diff[valid_avg_pct_diff > 0])
#     negative_pct_count_all = len(valid_avg_pct_diff[valid_avg_pct_diff < 0])
#     zero_pct_count_all = len(valid_avg_pct_diff[valid_avg_pct_diff == 0])
    
#     stats_data = [
#         ['Metric', 'Absolute Difference (g/ml)', 'Percentage Difference (%)'],
#         ['Count', f'{len(valid_avg_diff)}', f'{len(valid_avg_pct_diff)}'],
#         ['Mean', f'{valid_avg_diff.mean():.2f}', f'{valid_avg_pct_diff.mean():.2f}'],
#         ['Median', f'{valid_avg_diff.median():.2f}', f'{valid_avg_pct_diff.median():.2f}'],
#         ['Standard Deviation', f'{valid_avg_diff.std():.2f}', f'{valid_avg_pct_diff.std():.2f}'],
#         ['Minimum', f'{valid_avg_diff.min():.2f}', f'{valid_avg_pct_diff.min():.2f}'],
#         ['Maximum', f'{valid_avg_diff.max():.2f}', f'{valid_avg_pct_diff.max():.2f}'],
#         ['25th Percentile (Q1)', f'{valid_avg_diff.quantile(0.25):.2f}', f'{valid_avg_pct_diff.quantile(0.25):.2f}'],
#         ['75th Percentile (Q3)', f'{valid_avg_diff.quantile(0.75):.2f}', f'{valid_avg_pct_diff.quantile(0.75):.2f}'],
#         ['Overestimation Count', f'{positive_count} ({positive_count/len(valid_avg_diff)*100:.1f}%)', 
#          f'{positive_pct_count_all} ({positive_pct_count_all/len(valid_avg_pct_diff)*100:.1f}%)'],
#         ['Underestimation Count', f'{negative_count} ({negative_count/len(valid_avg_diff)*100:.1f}%)', 
#          f'{negative_pct_count_all} ({negative_pct_count_all/len(valid_avg_pct_diff)*100:.1f}%)'],
#         ['Accurate Prediction Count', f'{zero_count} ({zero_count/len(valid_avg_diff)*100:.1f}%)', 
#          f'{zero_pct_count_all} ({zero_pct_count_all/len(valid_avg_pct_diff)*100:.1f}%)'],
#         ['Net Bias', f'{(positive_count - negative_count)/len(valid_avg_diff)*100:+.1f}%', 
#          f'{(positive_pct_count_all - negative_pct_count_all)/len(valid_avg_pct_diff)*100:+.1f}%']
#     ]
    
#     table = plt.table(cellText=stats_data, 
#                      cellLoc='center', 
#                      loc='center',
#                      bbox=[0, 0, 1, 1])
#     table.auto_set_font_size(False)
#     table.set_fontsize(12)
#     table.scale(1, 2)
    
#     # Style the table
#     for i in range(len(stats_data)):
#         for j in range(len(stats_data[0])):
#             if i == 0:  # Header row
#                 table[(i, j)].set_facecolor('#4CAF50')
#                 table[(i, j)].set_text_props(weight='bold', color='white')
#             elif i % 2 == 1:  # Alternate row colors
#                 table[(i, j)].set_facecolor('#F5F5F5')
#             else:
#                 table[(i, j)].set_facecolor('#FFFFFF')
    
#     plt.title('Comprehensive Statistical Summary of Average Differences', 
#               fontsize=16, fontweight='bold', pad=20)
    
#     plt.tight_layout()
#     plt.savefig(r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\Evaluation\statistical_summary_table.png", 
#                 dpi=300, bbox_inches='tight', facecolor='white')
#     plt.show()
    
#     # Print comprehensive statistics
#     print_comprehensive_statistics(valid_avg_diff, valid_avg_pct_diff)
    
#     print(f"\n💾 All individual charts have been saved to separate files:")
#     print(f"   • avg_diff_point_distribution.png")
#     print(f"   • avg_diff_histogram.png") 
#     print(f"   • avg_pct_diff_point_distribution.png")
#     print(f"   • avg_pct_diff_histogram.png")
#     print(f"   • statistical_summary_table.png")

# def print_comprehensive_statistics(valid_avg_diff, valid_avg_pct_diff):
#     """Print comprehensive statistical information"""
#     print(f"\n📈 COMPREHENSIVE STATISTICAL ANALYSIS")
#     print("="*50)
    
#     # Basic statistics
#     print(f"\n📊 Basic Statistics:")
#     print(f"   Total Images Analyzed: {len(valid_avg_diff)}")
#     print(f"   Mean Absolute Difference: {valid_avg_diff.mean():.2f} ± {valid_avg_diff.std():.2f} g/ml")
#     print(f"   Mean Percentage Difference: {valid_avg_pct_diff.mean():.2f} ± {valid_avg_pct_diff.std():.2f}%")
    
#     # Direction analysis
#     positive_diff = len(valid_avg_diff[valid_avg_diff > 0])
#     negative_diff = len(valid_avg_diff[valid_avg_diff < 0])
#     print(f"\n🎯 Prediction Direction:")
#     print(f"   Overestimation: {positive_diff} images ({positive_diff/len(valid_avg_diff)*100:.1f}%)")
#     print(f"   Underestimation: {negative_diff} images ({negative_diff/len(valid_avg_diff)*100:.1f}%)")
#     print(f"   Net Bias: {(positive_diff - negative_diff)/len(valid_avg_diff)*100:+.1f}%")
    
#     # Performance classification
#     print(f"\n📋 Performance Classification:")
#     thresholds = [
#         (5, 10, "Excellent"),
#         (10, 20, "Good"), 
#         (20, 50, "Fair"),
#         (float('inf'), float('inf'), "Poor")
#     ]
    
#     for abs_thresh, pct_thresh, category in thresholds:
#         if abs_thresh == float('inf'):
#             count = len(valid_avg_diff[(np.abs(valid_avg_diff) > 20) | (np.abs(valid_avg_pct_diff) > 50)])
#         else:
#             count = len(valid_avg_diff[(np.abs(valid_avg_diff) <= abs_thresh) & (np.abs(valid_avg_pct_diff) <= pct_thresh)])
#         print(f"   {category}: {count} images ({count/len(valid_avg_diff)*100:.1f}%)")
    
#     # Distribution range analysis
#     print(f"\n📏 Distribution Ranges (Absolute Differences):")
#     for threshold in [5, 10, 15, 20, 30]:
#         within = len(valid_avg_diff[np.abs(valid_avg_diff) <= threshold])
#         print(f"   ±{threshold}g: {within} images ({within/len(valid_avg_diff)*100:.1f}%)")
    
#     print(f"\n📏 Distribution Ranges (Percentage Differences):")
#     for threshold in [10, 20, 30, 50, 100]:
#         within = len(valid_avg_pct_diff[np.abs(valid_avg_pct_diff) <= threshold])
#         print(f"   ±{threshold}%: {within} images ({within/len(valid_avg_pct_diff)*100:.1f}%)")

# if __name__ == "__main__":
#     plot_individual_avg_differences_analysis()
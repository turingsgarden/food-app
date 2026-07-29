"""
Comprehensive distribution analysis of average differences per dish,
adapted for eval_output_4.xlsx (long-format evaluation export).

This mimics the structure of the original 14-panel comprehensive script:
  A. avg_diff point distribution
  B. avg_diff histogram
  C. avg_pct_diff point distribution
  D. avg_pct_diff histogram
  E. Boxplot comparison
  F. Cumulative Distribution Function (CDF)
  G. Correlation scatter (abs vs pct)
  H. Error direction pie chart
  I. Performance category bar chart
  J. Performance distribution by error magnitude
  K. Statistical summary table
  L. 2D distribution heatmap
  M/N. Q-Q plots (normality tests)

DIFFERENCE FROM THE ORIGINAL:
eval_output_4.xlsx does not have ready-made 'avg_diff' / 'avg_pct_diff' /
'image_filename' columns. Instead it's a long-format export with a `table`
column that tags each row's role ('matched_ingredient', 'per_dish', etc.).
Per-ingredient errors live in the 'matched_ingredient' rows
(signed_error_g, pct_error), keyed by 'dish'. So this script first
rebuilds the per-image avg_diff / avg_pct_diff table by grouping
matched_ingredient rows by dish and averaging signed_error_g -> avg_diff
and pct_error -> avg_pct_diff. Everything after that mirrors the
original plotting logic.
"""

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
from scipy import stats
import warnings
warnings.filterwarnings('ignore')


def build_avg_diff_table(df):
    """
    Recreate the per-image avg_diff / avg_pct_diff table that the
    original script expected, from the matched_ingredient rows.
    """
    matched = df[df['table'] == 'matched_ingredient'].copy()

    grouped = (
        matched.groupby('dish')
        .agg(avg_diff=('signed_error_g', 'mean'),
             avg_pct_diff=('pct_error', 'mean'))
        .reset_index()
        .rename(columns={'dish': 'image_filename'})
    )
    return grouped


def plot_comprehensive_avg_differences_analysis():
    # File path (edit if needed)
    input_file = "eval_output_4.xlsx"

    # Read Excel file
    df = pd.read_excel(input_file)

    # Rebuild the per-image avg_diff / avg_pct_diff table
    unique_avg_data = build_avg_diff_table(df)

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
    fig.suptitle('Comprehensive Analysis of Average Differences per Dish', fontsize=18, fontweight='bold')

    # Define grid layout
    gs = fig.add_gridspec(4, 4)

    # 1. avg_diff point distribution (with positive/negative direction)
    ax1 = fig.add_subplot(gs[0, 0])
    x_positions = np.arange(len(valid_avg_diff))

    colors = ['red' if x > 0 else 'blue' for x in valid_avg_diff]
    sizes = [50 + abs(x) * 2 for x in valid_avg_diff]  # Size reflects difference magnitude

    ax1.scatter(x_positions, valid_avg_diff, alpha=0.7, s=sizes,
                c=colors, edgecolors='black', linewidth=0.5)

    ax1.axhline(y=0, color='black', linestyle='-', alpha=0.8, linewidth=2, label='Zero Line')
    ax1.axhline(y=valid_avg_diff.mean(), color='green', linestyle='--', alpha=0.8, linewidth=1.5,
                label=f'Mean: {valid_avg_diff.mean():.2f}')

    ax1.set_xlabel('Dish Index')
    ax1.set_ylabel('Average Difference (g)')
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

    ax2.set_xlabel('Average Difference (g)')
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
    pct_sizes = [50 + abs(x) / 5 for x in filtered_avg_pct_diff]

    ax3.scatter(filtered_x_positions, filtered_avg_pct_diff, alpha=0.7, s=pct_sizes,
                c=pct_colors, edgecolors='black', linewidth=0.5)

    ax3.axhline(y=0, color='black', linestyle='-', alpha=0.8, linewidth=2, label='Zero Line')
    ax3.axhline(y=filtered_avg_pct_diff.mean(), color='green', linestyle='--', alpha=0.8, linewidth=1.5,
                label=f'Mean: {filtered_avg_pct_diff.mean():.2f}%')

    ax3.set_xlabel('Dish Index')
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
                            labels=['Absolute Diff (g)', 'Percentage Diff (%)'])

    box_colors = ['lightblue', 'lightgreen']
    for patch, color in zip(box_plot['boxes'], box_colors):
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
    ax6.plot(sorted_pct / 10, cdf_pct, linewidth=3, color='red', label='Percentage Differences (/10)')

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

    mask_scatter = (np.abs(avg_diff_common) <= 50) & (np.abs(avg_pct_common) <= 200)
    scatter3 = ax7.scatter(avg_diff_common[mask_scatter], avg_pct_common[mask_scatter],
                            alpha=0.6, s=60, c=avg_diff_common[mask_scatter], cmap='coolwarm')

    ax7.axhline(y=0, color='red', linestyle='-', alpha=0.5, linewidth=1)
    ax7.axvline(x=0, color='red', linestyle='-', alpha=0.5, linewidth=1)
    ax7.set_xlabel('Average Absolute Difference (g)')
    ax7.set_ylabel('Average Percentage Difference (%)')
    ax7.set_title('G. Correlation: Absolute vs Percentage Differences',
                   fontsize=12, fontweight='bold')
    ax7.grid(True, alpha=0.3)

    cbar3 = plt.colorbar(scatter3, ax=ax7)
    cbar3.set_label('Absolute Difference (g)', rotation=270, labelpad=15)

    # 8. Error direction analysis pie chart
    ax8 = fig.add_subplot(gs[1, 3])
    positive_count = len(valid_avg_diff[valid_avg_diff > 0])
    negative_count = len(valid_avg_diff[valid_avg_diff < 0])
    zero_count = len(valid_avg_diff[valid_avg_diff == 0])

    pie_sizes = [positive_count, negative_count, zero_count]
    pie_labels = [f'Overestimation\n({positive_count})',
                  f'Underestimation\n({negative_count})',
                  f'Accurate\n({zero_count})']
    pie_colors = ['red', 'blue', 'green']

    wedges, texts, autotexts = ax8.pie(pie_sizes, labels=pie_labels, colors=pie_colors, autopct='%1.1f%%',
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
    bar_colors = ['green', 'lightgreen', 'orange', 'red']

    bars = ax9.bar(categories, counts, color=bar_colors, alpha=0.7, edgecolor='black')
    ax9.set_ylabel('Number of Dishes')
    ax9.set_title('I. Performance Classification', fontsize=12, fontweight='bold')
    ax9.tick_params(axis='x', rotation=45)

    for bar, count in zip(bars, counts):
        height = bar.get_height()
        ax9.text(bar.get_x() + bar.get_width() / 2., height + 0.1,
                  f'{count}\n({count/len(valid_avg_diff)*100:.1f}%)',
                  ha='center', va='bottom', fontsize=9)

    # 10. Performance distribution by error magnitude
    ax10 = fig.add_subplot(gs[2, 1])

    magnitude_bins = [0, 5, 10, 20, 50, float('inf')]
    bin_labels = ['0-5g', '5-10g', '10-20g', '20-50g', '50g+']
    bin_counts = []
    bin_means = []

    for i in range(len(magnitude_bins) - 1):
        lower = magnitude_bins[i]
        upper = magnitude_bins[i + 1]
        if upper == float('inf'):
            bmask = np.abs(valid_avg_diff) >= lower
        else:
            bmask = (np.abs(valid_avg_diff) >= lower) & (np.abs(valid_avg_diff) < upper)

        bin_data = valid_avg_diff[bmask]
        bin_counts.append(len(bin_data))
        bin_means.append(bin_data.mean() if len(bin_data) > 0 else 0)

    x_pos = range(len(bin_labels))
    ax10.bar(x_pos, bin_counts, alpha=0.7, color='lightblue',
             edgecolor='navy', label='Number of Dishes')

    ax10.set_xlabel('Absolute Difference Magnitude (g)')
    ax10.set_ylabel('Number of Dishes', color='blue')
    ax10.set_title('J. Performance Distribution by Error Magnitude',
                    fontsize=12, fontweight='bold')
    ax10.set_xticks(x_pos)
    ax10.set_xticklabels(bin_labels)

    ax10_secondary = ax10.twinx()
    ax10_secondary.plot(x_pos, bin_means, 'ro-', linewidth=2, markersize=8,
                         label='Mean Difference')
    ax10_secondary.set_ylabel('Mean Difference (g)', color='red')
    ax10_secondary.tick_params(axis='y', labelcolor='red')

    for i, count in enumerate(bin_counts):
        ax10.text(i, count + max(bin_counts) * 0.01, str(count),
                   ha='center', va='bottom', fontweight='bold')

    ax10.grid(True, alpha=0.3)

    # 11. Statistical information table
    ax11 = fig.add_subplot(gs[2, 2:])
    ax11.axis('off')

    stats_data = [
        ['Metric', 'Absolute Diff', 'Percentage Diff'],
        ['Count', len(valid_avg_diff), len(valid_avg_pct_diff)],
        ['Mean', f'{valid_avg_diff.mean():.2f} g', f'{valid_avg_pct_diff.mean():.2f}%'],
        ['Median', f'{valid_avg_diff.median():.2f} g', f'{valid_avg_pct_diff.median():.2f}%'],
        ['Std Dev', f'{valid_avg_diff.std():.2f} g', f'{valid_avg_pct_diff.std():.2f}%'],
        ['Min', f'{valid_avg_diff.min():.2f} g', f'{valid_avg_pct_diff.min():.2f}%'],
        ['Max', f'{valid_avg_diff.max():.2f} g', f'{valid_avg_pct_diff.max():.2f}%'],
        ['Q1 (25%)', f'{valid_avg_diff.quantile(0.25):.2f} g', f'{valid_avg_pct_diff.quantile(0.25):.2f}%'],
        ['Q3 (75%)', f'{valid_avg_diff.quantile(0.75):.2f} g', f'{valid_avg_pct_diff.quantile(0.75):.2f}%'],
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
    x = valid_avg_diff
    y = valid_avg_pct_diff[np.abs(valid_avg_pct_diff) <= 200]

    min_len = min(len(x), len(y))
    x_trimmed = x.iloc[:min_len]
    y_trimmed = y.iloc[:min_len]

    heatmap = ax12.hist2d(x_trimmed, y_trimmed, bins=20, cmap='YlOrRd')
    ax12.axhline(y=0, color='white', linestyle='-', alpha=0.5)
    ax12.axvline(x=0, color='white', linestyle='-', alpha=0.5)
    ax12.set_xlabel('Average Absolute Difference (g)')
    ax12.set_ylabel('Average Percentage Difference (%)')
    ax12.set_title('L. 2D Distribution Heatmap\n(High density areas)',
                    fontsize=12, fontweight='bold')

    plt.colorbar(heatmap[3], ax=ax12, label='Number of Dishes')

    # 13. Q-Q plot for absolute differences (normality test)
    ax13 = fig.add_subplot(gs[3, 2])
    stats.probplot(valid_avg_diff, dist="norm", plot=ax13)
    ax13.set_title('M. Q-Q Plot: Normality Test\n(Absolute Differences)',
                    fontsize=12, fontweight='bold')

    # 14. Q-Q plot for percentage differences
    ax14 = fig.add_subplot(gs[3, 3])
    filtered_pct_for_qq = valid_avg_pct_diff[np.abs(valid_avg_pct_diff) <= 100]
    stats.probplot(filtered_pct_for_qq, dist="norm", plot=ax14)
    ax14.set_title('N. Q-Q Plot: Normality Test\n(Percentage Differences)',
                    fontsize=12, fontweight='bold')

    plt.tight_layout()

    # Save image
    output_image = "comprehensive_avg_differences_analysis.png"
    plt.savefig(output_image, dpi=300, bbox_inches='tight', facecolor='white')
    plt.show()

    print_comprehensive_statistics(valid_avg_diff, valid_avg_pct_diff)

    print(f"\n💾 Comprehensive analysis chart saved to: {output_image}")


def print_comprehensive_statistics(valid_avg_diff, valid_avg_pct_diff):
    """Print comprehensive statistical information"""
    print(f"\n📈 COMPREHENSIVE STATISTICAL ANALYSIS")
    print("=" * 50)

    print(f"\n📊 Basic Statistics:")
    print(f"   Total Dishes Analyzed: {len(valid_avg_diff)}")
    print(f"   Mean Absolute Difference: {valid_avg_diff.mean():.2f} ± {valid_avg_diff.std():.2f} g")
    print(f"   Mean Percentage Difference: {valid_avg_pct_diff.mean():.2f} ± {valid_avg_pct_diff.std():.2f}%")

    positive_diff = len(valid_avg_diff[valid_avg_diff > 0])
    negative_diff = len(valid_avg_diff[valid_avg_diff < 0])
    print(f"\n🎯 Prediction Direction:")
    print(f"   Overestimation: {positive_diff} dishes ({positive_diff/len(valid_avg_diff)*100:.1f}%)")
    print(f"   Underestimation: {negative_diff} dishes ({negative_diff/len(valid_avg_diff)*100:.1f}%)")
    print(f"   Net Bias: {(positive_diff - negative_diff)/len(valid_avg_diff)*100:+.1f}%")

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
        print(f"   {category}: {count} dishes ({count/len(valid_avg_diff)*100:.1f}%)")

    print(f"\n📏 Distribution Ranges (Absolute Differences):")
    for threshold in [5, 10, 15, 20, 30]:
        within = len(valid_avg_diff[np.abs(valid_avg_diff) <= threshold])
        print(f"   ±{threshold}g: {within} dishes ({within/len(valid_avg_diff)*100:.1f}%)")

    print(f"\n📏 Distribution Ranges (Percentage Differences):")
    for threshold in [10, 20, 30, 50, 100]:
        within = len(valid_avg_pct_diff[np.abs(valid_avg_pct_diff) <= threshold])
        print(f"   ±{threshold}%: {within} dishes ({within/len(valid_avg_pct_diff)*100:.1f}%)")


if __name__ == "__main__":
    plot_comprehensive_avg_differences_analysis()

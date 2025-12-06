import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import os

def read_and_analyze_excel(file_path):
    """
    Read the Excel file and analyze ingredient name prediction accuracy.
    """
    try:
        # Read Excel file
        df = pd.read_excel(file_path)
        print(f"Successfully loaded Excel file with {len(df)} rows.")
        
        # Handle merged cells — forward fill dish_id
        if 'dish_id' in df.columns:
            df['dish_id'] = df['dish_id'].ffill()
            print(f"Number of unique dish_id values after processing: {df['dish_id'].nunique()}")
        
        # Check if confidence column exists
        if 'confidence' not in df.columns:
            print("The Excel file does not contain a 'confidence' column.")
            return None
        
        # Display confidence value distribution
        print("\nConfidence Value Distribution:")
        confidence_counts = df['confidence'].value_counts(dropna=False)
        print(confidence_counts)
        
        # Determine correct predictions
        # ✅ High and 🟡 Contained are considered correct
        df['is_correct'] = df['confidence'].isin(['✅ High', '🟡 Contained'])
        
        # Compute statistics
        total_predictions = len(df)
        correct_predictions = df['is_correct'].sum()
        incorrect_predictions = total_predictions - correct_predictions
        
        correct_percentage = (correct_predictions / total_predictions * 100) if total_predictions > 0 else 0
        incorrect_percentage = 100 - correct_percentage
        
        print("\n" + "="*60)
        print("Statistics Summary:")
        print(f"Total Predictions: {total_predictions:,}")
        print(f"Correct Predictions: {correct_predictions:,} ({correct_percentage:.2f}%)")
        print(f"Incorrect Predictions: {incorrect_predictions:,} ({incorrect_percentage:.2f}%)")
        print("="*60)
        
        return {
            'df': df,
            'total_predictions': total_predictions,
            'correct_predictions': correct_predictions,
            'incorrect_predictions': incorrect_predictions,
            'correct_percentage': correct_percentage,
            'incorrect_percentage': incorrect_percentage
        }
        
    except Exception as e:
        print(f"Error occurred while reading Excel file: {str(e)}")
        return None


def plot_accuracy_bar_chart(results):
    """
    Draw a clean, modern bar chart showing prediction accuracy.
    (Summary box originally on right side under legend — currently disabled)
    """
    # Set font and visual style
    plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei']
    plt.rcParams['axes.unicode_minus'] = False
    
    fig, ax = plt.subplots(figsize=(8, 6))
    
    # Data
    categories = ['Correct', 'Incorrect']
    values = [results['correct_predictions'], results['incorrect_predictions']]
    percentages = [results['correct_percentage'], results['incorrect_percentage']]
    
    # Colors
    colors = ["blue", "red"]
    
    # Draw bar chart
    bars = ax.bar(
        categories, values,
        color=colors, width=0.55, alpha=0.9,
        edgecolor='white', linewidth=1.2,
        label=['Correct', 'Incorrect']
    )
    
    # Title (with line break)
    ax.set_title(
        ('Ingredient Name Prediction Accuracy Overview'
         '\n(volume augmented)'),
        fontsize=18,
        fontweight='bold',
        pad=20
    )
    
    ax.set_ylabel('Count', fontsize=14, fontweight='medium')
    
    # Remove unnecessary lines
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.yaxis.grid(True, linestyle='--', alpha=0.25)

    # Add count and percentage labels
    max_height = max(values)
    for bar, value, pct in zip(bars, values, percentages):
        height = bar.get_height()
        
        # Number above bar
        ax.text(
            bar.get_x() + bar.get_width()/2,
            height + max_height * 0.02,
            f'{value:,}',
            ha='center', va='bottom',
            fontsize=12, fontweight='bold'
        )
        
        # Percentage inside bar
        ax.text(
            bar.get_x() + bar.get_width()/2,
            height * 0.5,
            f'{pct:.1f}%',
            ha='center', va='center',
            fontsize=13, color='white', fontweight='bold'
        )
    
    # --- Legend ---
    legend = ax.legend(
        ['Correct', 'Incorrect'],
        loc='upper right',
        fontsize=12,
        frameon=False
    )

    plt.tight_layout()
    plt.show()
    
    return fig


def main():
    # Excel file path
    file_path = "model_output_analysis/mass_prediction_data_and_result/mass_comparison.xlsx"
    
    # Check file existence
    if not os.path.exists(file_path):
        print(f"Error: File does not exist: {file_path}")
        print("Please verify the file path.")
        return
    
    print("="*70)
    print("Ingredient Name Prediction Accuracy Analysis")
    print("="*70)
    
    # Read and analyze
    results = read_and_analyze_excel(file_path)
    
    if results:
        print("\n" + "="*60)
        print("Generating accuracy bar chart...")
        print("="*60)
        plot_accuracy_bar_chart(results)
        
        # Save statistical summary to CSV
        output_file = "prediction_analysis_results.csv"
        summary_df = pd.DataFrame({
            'Metric': ['Total Predictions', 'Correct Predictions', 'Incorrect Predictions', 
                      'Correct Percentage (%)', 'Incorrect Percentage (%)'],
            'Value': [results['total_predictions'], results['correct_predictions'],
                     results['incorrect_predictions'], 
                     f"{results['correct_percentage']:.2f}",
                     f"{results['incorrect_percentage']:.2f}"]
        })
        
        summary_df.to_csv(output_file, index=False, encoding='utf-8-sig')
        print(f"\n✓ Summary saved to: {output_file}")
        
        # Detailed statistics
        print("\nDetailed Stats:")
        print("-"*50)
        
        # Confidence value statistics
        confidence_stats = results['df']['confidence'].value_counts().reset_index()
        confidence_stats.columns = ['Confidence', 'Count']
        confidence_stats['Percentage'] = (confidence_stats['Count'] / len(results['df']) * 100).round(2)
        print("Confidence Value Summary:")
        print(confidence_stats.to_string(index=False))
        
        # Stats by dish_id
        if 'dish_id' in results['df'].columns:
            print("\n" + "-"*50)
            print("Stats by Dish ID (first 10 rows):")
            dish_stats = results['df'].groupby('dish_id')['is_correct'].agg(['count', 'sum']).reset_index()
            dish_stats.columns = ['dish_id', 'total_predictions', 'correct_predictions']
            dish_stats['correct_rate(%)'] = (dish_stats['correct_predictions'] / dish_stats['total_predictions'] * 100).round(2)
            print(dish_stats.head(10).to_string(index=False))
            
            # Accuracy distribution
            print("\n" + "-"*50)
            print("Accuracy Distribution by Dish:")
            bins = [0, 20, 40, 60, 80, 100]
            labels = ['0-20%', '20-40%', '40-60%', '60-80%', '80-100%']
            dish_stats['rate_group'] = pd.cut(dish_stats['correct_rate(%)'], bins=bins, labels=labels, right=False)
            rate_dist = dish_stats['rate_group'].value_counts().sort_index()
            
            for group, count in rate_dist.items():
                percentage = (count / len(dish_stats) * 100)
                print(f"{group}: {count} dishes ({percentage:.1f}%)")
    
    print("\n" + "="*70)
    print("Analysis Complete!")
    print("="*70)


if __name__ == "__main__":
    main()


import pandas as pd
import os
import sys

def aggregate_trunk_sway(file_path):
    df = pd.read_csv(file_path)
    mean = df.mean()
    std = df.std()
    part_id = os.path.basename(file_path).split('_')[0]
    agg_data = {
        'part_id': part_id,
        'trunk_swing_mean': mean.iloc[0],
        'trunk_swing_std': std.iloc[0]
    }
    return agg_data
 
def aggregate_step_width(file_path):
    df = pd.read_csv(file_path)
    mean = df.mean()
    std = df.std()
    part_id = os.path.basename(file_path).split('_')[0]
    agg_data = {
        'part_id': part_id,
        'heel_separation_left_mean': mean.iloc[0],
        'heel_separation_left_std': std.iloc[0],
        'heel_separation_right_mean': mean.iloc[1],
        'heel_separation_right_std': std.iloc[1]
    }
    return agg_data

def aggregate_hand_separation(file_path):
    df = pd.read_csv(file_path)
    mean = df.mean()
    std = df.std()
    part_id = os.path.basename(file_path).split('_')[0]
    agg_data = {
        'part_id': part_id,
        'hand_separation_left_mean': mean.iloc[0],
        'hand_separation_left_std': std.iloc[0],
        'hand_separation_right_mean': mean.iloc[1],
        'hand_separation_right_std': std.iloc[1]
    }
    return agg_data

def aggregate_arm_separation(file_path):
    df = pd.read_csv(file_path)
    mean = df.mean()
    std = df.std()
    part_id = os.path.basename(file_path).split('_')[0]
    agg_data = {
        'part_id': part_id,
        'arm_separation_left_mean': mean.iloc[0],
        'arm_separation_left_std': std.iloc[0],
        'arm_separation_right_mean': mean.iloc[1],
        'arm_separation_right_std': std.iloc[1]
    }
    return agg_data

def process_demographics(file_path):
    df = pd.read_csv(file_path)
    return df.to_dict('records')[0]

def main():
    if len(sys.argv) != 7:
        print("Usage: python dataCleaning.py <demographics_csv> <arm_separation_csv> <hand_separation_csv> <trunk_swing_csv> <heel_separation_csv> <output_csv>")
        sys.exit(1)
    
    demographics_path = sys.argv[1]
    arm_separation_path = sys.argv[2]
    hand_separation_path = sys.argv[3]
    trunk_swing_path = sys.argv[4]
    heel_separation_path = sys.argv[5]
    output_path = sys.argv[6]
    
    try:
        # Process each CSV file
        demographics_data = process_demographics(demographics_path)
        trunk_data = aggregate_trunk_sway(trunk_swing_path)
        step_data = aggregate_step_width(heel_separation_path)
        arm_data = aggregate_arm_separation(arm_separation_path)
        hand_data = aggregate_hand_separation(hand_separation_path)
        
        # Combine all data
        combined_data = {
            **demographics_data,
            **trunk_data,
            **step_data,
            **arm_data,
            **hand_data
        }
        
        # Remove duplicate part_id entries (keep demographics Name)
        if 'part_id' in combined_data and 'Name' in combined_data:
            del combined_data['part_id']
        
        # Create DataFrame and save
        result_df = pd.DataFrame([combined_data])
        result_df.to_csv(output_path, index=False)
        
        print(f"Cleansed data saved to: {output_path}")
        print("Combined data columns:", list(result_df.columns))
        print(result_df.head())
        
    except Exception as e:
        print(f"Error processing files: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()

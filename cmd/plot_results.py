import sys
import pandas as pd
import matplotlib.pyplot as plt
from datetime import datetime

if len(sys.argv) != 3:
    print("Usage: python plot_results.py <input .csv file> <output .png file>")
    sys.exit(1)

input_csv = sys.argv[1]
output_image = sys.argv[2]

# Read data from CSV file using pandas
data = pd.read_csv(input_csv)

# Extract and convert data for plotting
dates = []
columns = {}

for col in data.columns[1:]:
    columns[col] = []

for index, row in data.iterrows():
    date_str = row['run']
    dates.append(datetime.strptime(date_str, '%Y-%m%d-%H%M%S'))
    
    for col in columns.keys():
        columns[col].append(row[col])

# Plotting
plt.figure(figsize=(10, 6))

for col, values in columns.items():
    plt.plot(dates, values, marker='o', label=col)

plt.xlabel('Date')
plt.ylabel('Counts')
plt.title('Test Results Over Time')
plt.xticks(rotation=45)
plt.legend()

plt.tight_layout()

# Save the plot as a PNG image
plt.savefig(output_image)

# Optional: Clear the plot
plt.clf()
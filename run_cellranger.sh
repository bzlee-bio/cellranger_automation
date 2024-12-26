#!/bin/bash

# Check if the target folder and max concurrent jobs are provided
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <target_folder> <max_concurrent_jobs>"
  exit 1
fi

# Input arguments
target_folder=$1
max_jobs=$2

# Configuration file path
config_file="config.txt"

# Check if configuration file exists
if [ ! -f "$config_file" ]; then
  echo "Error: Configuration file '$config_file' not found."
  exit 1
fi

# Read configuration values
cellranger_path=$(grep '^cellranger_path=' "$config_file" | cut -d '=' -f 2)
cellranger_path="${cellranger_path}/bin/cellranger"
reference_path=$(grep '^reference_path=' "$config_file" | cut -d '=' -f 2)

# Validate configuration values
if [ -z "$cellranger_path" ] || [ -z "$reference_path" ]; then
  echo "Error: Missing configuration values in '$config_file'."
  echo "Ensure 'cellranger_path' and 'reference_path' are set."
  exit 1
fi

# Logging paths
echo "Target folder: $target_folder"
echo "Cellranger executable: $cellranger_path"
echo "Reference dataset: $reference_path"
echo "Max concurrent jobs: $max_jobs"

# Create "cellranger" folder under the target folder
cellranger_folder="${target_folder}/cellranger"
mkdir -p "$cellranger_folder"
echo "Created folder: $cellranger_folder"

# Raw fastq folder
fastq_folder="${target_folder}/Raw/fastq"

# Check if fastq folder exists
if [ ! -d "$fastq_folder" ]; then
  echo "Error: Fastq folder does not exist: $fastq_folder"
  exit 1
fi

# Function to run a single cellranger job
run_cellranger() {
  local fol=$1
  local fol_name
  fol_name=$(basename "$fol")
  local output_folder="${cellranger_folder}/${fol_name}"
  local log_file="${output_folder}/cellranger_${fol_name}.log"

  echo "Processing folder: $fol_name"

  # Case 1: The sample is already processed if 'outs' folder exists
  if [ -d "${output_folder}/outs" ]; then
    echo "Sample '$fol_name' is already processed (found '${output_folder}/outs'). Skipping..."
    return 0
  fi

  # Case 2: The output folder exists but does not have an 'outs' directory => remove and re-run
  if [ -d "$output_folder" ]; then
    echo "Output folder '$output_folder' found, but missing 'outs' subfolder. Removing and re-running..."
    rm -rf "$output_folder"
  fi

  # Build and log the exact command
  cmd="$cellranger_path count \
    --id=$fol_name \
    --transcriptome=$reference_path \
    --create-bam=true \
    --fastqs=$fol \
    --sample=$fol_name \
    --output-dir=$output_folder \
    --disable-ui"

  mkdir -p "$output_folder"

  # Log the command that will be run
  echo "Running command:" > "$log_file"
  echo "$cmd" >> "$log_file"
  echo "----------------------------------------" >> "$log_file"

  # Run the command
  eval "$cmd"
  if [ $? -eq 0 ]; then
    echo "Cellranger run complete for $fol_name. Logs saved to $log_file"
  else
    echo "Error occurred during cellranger run for $fol_name. Check log: $log_file"
  fi
}

# Export function and variables for parallel processing
export -f run_cellranger
export cellranger_path reference_path cellranger_folder

# Run jobs in parallel using xargs
find "$fastq_folder" -mindepth 1 -maxdepth 1 -type d \
  | xargs -I {} -P "$max_jobs" bash -c 'run_cellranger "{}"'

echo "All Cellranger runs completed."

########################################
# STEP: Verify all folders have outs
########################################

# Create a summary report (TSV format) in the cellranger folder
report_file="${cellranger_folder}/cellranger_completion_report.tsv"
echo -e "Sample\tOutput_Folder_Exists\tOuts_Subfolder_Exists" > "$report_file"

# Check each folder in Raw/fastq
while IFS= read -r fol; do
  fol_name=$(basename "$fol")
  output_folder="${cellranger_folder}/${fol_name}"

  # Defaults
  output_exists="No"
  outs_exists="No"

  # Does the output folder exist?
  if [ -d "$output_folder" ]; then
    output_exists="Yes"
    # Check if 'outs' folder is present
    if [ -d "${output_folder}/outs" ]; then
      outs_exists="Yes"
    fi
  fi

  # Write TSV line: Sample, Output folder, Outs folder
  echo -e "${fol_name}\t${output_exists}\t${outs_exists}" >> "$report_file"
done < <(find "$fastq_folder" -mindepth 1 -maxdepth 1 -type d)

echo "TSV report saved to: $report_file"
echo "Done."

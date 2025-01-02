#!/bin/bash
# MP3 Splitter Script
# Author: Ruben Barkow-Kuder
# Script to split an MP3 file into chunks, maintaining silence at the end of each chunk

# Function to show help/usage information
show_help() {
  echo "Usage: $0 [options] <MP3 file>"
  echo "Options:"
  echo "  -h            Show this help"
  echo "  -n <number>   Number of chunks (default: 10)"
  echo "  -f <output>   Output directory (default: directory with subfolder)"
  echo "  -v            Verbose mode (show detailed output)"
}

# Default values
num_chunks=10
output_dir=""
verbose=False

# Parse options
while getopts "hvn:f:" opt; do
  case "$opt" in
    h) show_help; exit 0 ;;
    n) num_chunks=$OPTARG ;;
    f) output_dir=$OPTARG ;;
    v) verbose=True ;;
    ?) show_help; exit 1 ;;
  esac
done

# Shift positional arguments
shift $((OPTIND - 1))
if [ $# -eq 0 ]; then
  echo "Error: Please provide an MP3 file."
  show_help
  exit 1
fi

# Input file and default output directory
input_file="$1"

# Set default output directory
if [ -z "$output_dir" ]; then
  output_dir=$(dirname "$input_file")/$(basename "$input_file" .mp3)
fi

# Check if output directory exists, create a new one with date if it does
if [ -d "$output_dir" ]; then
  timestamp=$(date +%Y%m%d%H%M%S)
  new_output_dir="$output_dir ($timestamp)"
  if $verbose; then echo "Output directory '$output_dir' exists. Creating '$new_output_dir'"; fi
  output_dir="$new_output_dir"
fi

# Create output directory
if [ ! -d "$output_dir" ]; then
  if $verbose; then echo "Creating output directory: $output_dir"; fi
  mkdir -p "$output_dir" || { echo "Error: Could not create output directory." >&2; exit 1; }
fi
# Check if ffmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
  echo "ffmpeg is not installed. Install it with: sudo apt install ffmpeg"
  exit 1
fi

# Check if pipx is installed
if ! command -v pipx &> /dev/null; then
  echo "pipx is not installed. Install it with: sudo apt install pipx"
  exit 1
fi

# Check if the virtual environment exists in pipx
env_name="mp3_splitter_env"
if ! pipx list | grep -q "$env_name"; then
  echo "Creating virtual Python environment with pipx..."
  pipx install pydub
fi

# Create the output directory
if [ "$verbose" = "True" ]; then
  echo "Creating the folder $output_dir"
fi
mkdir -p "$output_dir"

# Python script for splitting the audio
pipx run --spec pydub python3 - <<EOF
from pydub import AudioSegment, silence
import os

# Input file and parameters
input_file = "$input_file"
output_dir = "$output_dir"
num_chunks = $num_chunks
verbose = $verbose

if verbose:
    print(f"Loading audio file: {input_file}")
audio = AudioSegment.from_file(input_file)

# Finde Stille-Segmente
silence_segments = silence.detect_silence(audio, min_silence_len=1000, silence_thresh=-40)

# Erstelle Chunks inklusive Stille
chunks = []
last_end = 0
for start, end in silence_segments:
    # Füge den Audioabschnitt vor der Stille hinzu
    if start > last_end:
        chunks.append(audio[last_end:start])
    # Füge das Stille-Segment hinzu
    chunks.append(audio[start:end])
    last_end = end

# Füge den restlichen Audioabschnitt nach der letzten Stille hinzu
if last_end < len(audio):
    chunks.append(audio[last_end:])

# Gruppiere Chunks basierend auf der maximalen Chunk-Dauer
max_chunk_duration = len(audio) // num_chunks
grouped_chunks = []
current_chunk = AudioSegment.empty()

for chunk in chunks:
    if len(current_chunk) + len(chunk) <= max_chunk_duration:
        current_chunk += chunk
    else:
        grouped_chunks.append(current_chunk)
        current_chunk = chunk

# Füge den letzten Chunk hinzu
grouped_chunks.append(current_chunk)

# Speichere die Chunks
os.makedirs(output_dir, exist_ok=True)
for i, chunk in enumerate(grouped_chunks):
    filename = f"{str(i + 1).zfill(2)}_{os.path.basename(input_file)}"
    output_path = os.path.join(output_dir, filename)
    chunk.export(output_path, format="mp3", bitrate="320k") # Bitrate hinzugefügt
    if verbose:
        print(f"Exported chunk {i + 1}: {output_path}")

print(f"Audio file split into {len(grouped_chunks)} parts in directory '{output_dir}'.")
EOF

# Final message
if [ "$verbose" = "True" ]; then
  echo "The script has been executed successfully."
fi
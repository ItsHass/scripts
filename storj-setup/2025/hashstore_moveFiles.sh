#!/bin/bash

# Variables for source and destination
SOURCE_DIR="/path/to/source"
DEST_DIR="/path/to/destination"

# Move files and directories from source to destination
mv "${SOURCE_DIR}"/* "${DEST_DIR}/" &&

# Validate if source is empty and rename it
([ "$(ls -A "${SOURCE_DIR}")" ] || mv "${SOURCE_DIR}" "${SOURCE_DIR}_old")

# Print status
if [ $? -eq 0 ]; then
  echo "Files moved and source directory renamed successfully."
else
  echo "An error occurred during the operation."
fi

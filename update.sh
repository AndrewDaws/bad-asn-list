#!/bin/bash

exit_script() {
  # Declare local variables
  local return_code

  # Initialize local variables
  return_code="1"

  # Input parameter provided
  if [[ -n "${1}" ]]; then
    # Check against valid return codes
    if [[ "${1}" -eq 0 || "${1}" -eq 1 ]]; then
      # Overwrite return code
      return_code="${1}"
    fi
  fi

  # Exit script with return code
  exit "${return_code}"
}

abort_script() {
  # Declare local variables
  local script_name

  # Initialize local variables
  script_name="$(basename "${0}")"

  # Print error message
  echo "Aborting ${script_name}"
  
  # Check for error messages
  if [[ -n "${*}" ]]; then
    # Treat each input parameter as a separate line
    for error_msg in "${@}"; do
      echo "  ${error_msg}"
    done
  fi

  # Exit script with error
  exit_script "1"
}

is_installed() {
  # Returns 0 if application is installed or error if it is not
  if which "${1}" | grep -o "${1}" > /dev/null; then
    return 0
  else
    return 1
  fi
}

check_connectivity() {
  # Declare local variables
  local test_address
  local test_count
  local test_timeout
  local return_code

  # Initialize local variables
  if [[ -n "${1}" ]]; then
    test_address="${1}"
  else
    test_address="8.8.8.8"
  fi
  test_count="1"
  test_timeout="5"
  return_code="-1"

  # Test connectivity with ping
  # Check if ping is installed
  if is_installed ping; then
    if ping \
      -c "${test_count}" \
      "${test_address}" \
      &> /dev/null; then
      return_code="0"
    else
      return_code="1"
    fi
  fi

  # Test connectivity with wget if not previously successful
  if [[ "${return_code}" -ne 0 ]]; then
    # Check if wget is installed
    if is_installed wget; then
      if wget \
        --quiet \
        --timeout="${test_timeout}" \
        --tries="${test_count}" \
        --spider \
        "${test_address}" \
        &> /dev/null; then
        return_code="0"
      else
        return_code="1"
      fi
    fi
  fi

  # Test connectivity with curl if not previously successful
  if [[ "${return_code}" -ne 0 ]]; then
    # Check if curl is installed
    if is_installed curl; then
      if curl \
        --silent \
        --connect-timeout "${test_timeout}" \
        --max-time "${test_timeout}" \
        "${test_address}" \
        &> /dev/null; then
        return_code="0"
      else
        return_code="1"
      fi
    fi
  fi

  # Return 0 if connected, 1 if not connected, or -1 if no tools installed
  return "${return_code}"
}

# Format columns and remove unwanted characters
format_file() {
  # Declare local variables
  local input_file

  # Initialize local variables
  input_file="${*}"

  # Check if input file variable is set
  if [[ -z "${input_file}" ]]; then
    # Error finding input file
    abort_script "ASN input file error" "Input file not provided!"
  fi

  # Check if input file is not missing
  if [[ ! -f "${input_file}" ]]; then
    # Error missing input file
    abort_script "ASN input file error" "Input file does not exist!"
  fi

  # Check if input file is not empty
  if [[ ! -s "${input_file}" ]]; then
    # Error empty input file
    abort_script "ASN input file error" "Input file is empty!"
  fi

  # Format each individual line
  rm -f "${input_file}-formatted"
  while read currentLine || [ -n "${currentLine}" ]; do
    currentASN="$(echo "${currentLine}" | grep -o -P '^[^,]+' | grep -o -P '[0-9]+')"

    # Check if current line contains an ASN
    if [[ -n "${currentASN}" ]]; then
      currentEntity="$( \
        echo "${currentLine}" \
        | grep -o -P '^\"?[0-9]+\"?,\s*\K.*$' \
        | sed 's/^"\([^"]\)/\1/' \
        | sed 's/["/]\+[^"/]*$//')"
      echo "${currentASN},\"${currentEntity}\"" >> "${input_file}-formatted"
    fi
  done < "${input_file}"
  rm -f "${input_file}"
  (echo "ASN,Entity"; cat "${input_file}-formatted") > "${input_file}"
  rm -f "${input_file}-formatted"
}

# Fix invalid lines, sort, and remove duplicates
clean_file() {
  # Declare local variables
  local input_file

  # Initialize local variables
  input_file="${*}"

  # Check if input file variable is set
  if [[ -z "${input_file}" ]]; then
    # Error finding input file
    abort_script "ASN input file error" "Input file not provided!"
  fi

  # Check if input file is not missing
  if [[ ! -f "${input_file}" ]]; then
    # Error missing input file
    abort_script "ASN input file error" "Input file does not exist!"
  fi

  # Check if input file is not empty
  if [[ ! -s "${input_file}" ]]; then
    # Error empty input file
    abort_script "ASN input file error" "Input file is empty!"
  fi

  # Ensure file is formatted correctly first
  format_file "${input_file}"

  # Sort and remove duplicate entries
  rm -f "${input_file}-cleaned"
  grep -o -P '^\"?[0-9]+\"?,\"?.+\"?$' "${input_file}" \
    | sort -n -t ',' -k 1,2 \
    | sort -n -u -t ',' -k 1,1 \
    > "${input_file}-cleaned"
  rm -f "${input_file}"
  (echo "ASN,Entity"; cat "${input_file}-cleaned") > "${input_file}"
  rm -f "${input_file}-cleaned"
}

# Download GeoIP ASN lists
download_geoip_lists() {
  # Declare local variables
  local output_file
  local maxmind_license_key
  local maxmind_config_file

  # Initialize local variables
  output_file="${*}"
  maxmind_license_key=""
  maxmind_config_file="${PWD}/maxmind.ini"

  # Check if output file variable is set
  if [[ -z "${output_file}" ]]; then
    # Error finding output file
    abort_script "MaxMind ASN lists download error" "Output file not provided!"
  fi

  # Find current MaxMind license key from config file
  if [[ -f "${maxmind_config_file}" ]]; then
    # Found MaxMind config file
    source "${maxmind_config_file}"
  fi

  # Find current MaxMind license key from environment
  if [[ -n "${MAXMIND_LICENSE_KEY}" ]]; then
    # Found MaxMind license key variable from config file, or in environment
    maxmind_license_key="${MAXMIND_LICENSE_KEY}"
  fi

  # Check if MaxMind license variable is set
  if [[ -z "${maxmind_license_key}" ]]; then
    # Error finding MaxMind license key
    abort_script "MaxMind ASN lists preprocess error" "Failed to find license key!"
  fi

  # Check if MaxMind domain is valid and accessible
  if ! check_connectivity "download.maxmind.com"; then
    # Error checking MaxMind connectivity
    abort_script "MaxMind ASN lists preprocess error" "No connection to MaxMind!"
  fi

  # Download current ASN lists
  rm -f "${output_file}"
  if ! curl \
    --silent \
    "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN-CSV&license_key=${maxmind_license_key}&suffix=zip" \
    --output "${output_file}"; then
    # Error downloading ASN lists
    rm -f "${output_file}"
    abort_script "MaxMind ASN lists download error" "Failed to download!"
  fi

  # Check if downloaded ASN lists is not empty or missing
  if [[ ! -f "${output_file}" ]]; then
    # Error empty or missing ASN lists
    rm -f "${output_file}"
    abort_script "MaxMind ASN lists download error" "Download file does not exist!"
  fi

  # Check if downloaded ASN lists is not empty or missing
  if [[ ! -s "${output_file}" ]]; then
    # Error empty or missing ASN lists
    rm -f "${output_file}"
    abort_script "MaxMind ASN lists download error" "Download file is empty!"
  fi

  # Check if downloaded ASN lists contains a database error
  if head -1 "${output_file}" | grep -q "Database edition not found"; then
    # Error invalid MaxMind database
    rm -f "${output_file}"
    abort_script "MaxMind ASN lists download error" "Database is invalid!"
  fi

  # Check if downloaded ASN lists contains a license error
  if head -1 "${output_file}" | grep -q "Invalid license key"; then
    # Error invalid MaxMind license key
    rm -f "${output_file}"
    abort_script "MaxMind ASN lists download error" "License key is invalid!"
  fi

  # Check if downloaded ASN lists contains a suffix error
  if head -1 "${output_file}" | grep -q "Invalid suffix"; then
    # Error invalid MaxMind suffix
    rm -f "${output_file}"
    abort_script "MaxMind ASN lists download error" "Suffix is invalid!"
  fi
}

# Update entity names with correct names
update_file() {
  # Declare local variables
  local input_file
  local geoip_file_name
  local geoip_zip_file
  local geoip_unzip_folder

  # Initialize local variables
  input_file="${*}"
  geoip_file_name="GeoLite2-ASN-CSV"
  geoip_zip_file="${PWD}/${geoip_file_name}.zip"
  geoip_unzip_folder="${PWD}/${geoip_file_name}"

  # Check if input file variable is set
  if [[ -z "${input_file}" ]]; then
    # Error finding input file
    abort_script "ASN input file error" "Input file not provided!"
  fi

  # Check if input file is not missing
  if [[ ! -f "${input_file}" ]]; then
    # Error missing input file
    abort_script "ASN input file error" "Input file does not exist!"
  fi

  # Check if input file is not empty
  if [[ ! -s "${input_file}" ]]; then
    # Error empty input file
    abort_script "ASN input file error" "Input file is empty!"
  fi

  # Download ASN lists
  download_geoip_lists "${geoip_zip_file}"

  # Extract zip file
  rm -rf "${geoip_unzip_folder}"
  mkdir -p "${PWD}/${geoip_file_name}"
  unzip -j \
    -o "${geoip_zip_file}" \
    ${geoip_file_name}_*/* \
    -d "${geoip_unzip_folder}" \
    &> /dev/null
  rm -f "${geoip_zip_file}"

  # Lookup and format each individual line
  rm -f "${input_file}-updated"
  while read currentLine || [ -n "${currentLine}" ]; do
    # Find ASN
    currentASN="$( \
      echo "${currentLine}" \
      | grep -o -P '^[^,]+' \
      | grep -o -P '[0-9]+')"

    # Check if current line contains an ASN
    if [[ -n "${currentASN}" ]]; then
      # Find entity in IPv4 GeoIP ASN list
      currentEntity="$( \
        grep -m1 -o -P '^[^,]+,\s*\K'"${currentASN}"',\s*\K.+$' \
        "${geoip_unzip_folder}/GeoLite2-ASN-Blocks-IPv4.csv" \
        | sed 's/^"\([^"]\)/\1/' \
        | sed 's/["/]\+[^"/]*$//')"
      
      # Check if entity was not set
      if [[ -z "${currentEntity}" ]]; then
        # Find entity in IPv6 GeoIP ASN list
        currentEntity="$( \
          grep -m1 -o -P '^[^,]+,\s*\K'"${currentASN}"',\s*\K.+$' \
          "${geoip_unzip_folder}/GeoLite2-ASN-Blocks-IPv6.csv" \
          | sed 's/^"\([^"]\)/\1/' \
          | sed 's/["/]\+[^"/]*$//')"
      fi

      # Check if entity was not set
      if [[ -z "${currentEntity}" ]]; then
        # Set to previous entity
        currentEntity="$( \
          echo "${currentLine}" \
          | grep -o -P '^\"?[0-9]+\"?,\s*\K.*$' \
          | sed 's/^"\([^"]\)/\1/' \
          | sed 's/["/]\+[^"/]*$//')"
      fi

      # Check if entity was not set
      if [[ -z "${currentEntity}" ]]; then
        # Default to UNKNOWN entity
        currentEntity="UNKNOWN"
      fi

      # Save to ASN list
      echo "${currentASN},\"${currentEntity}\"" >> "${input_file}-updated"
    fi
  done < "${input_file}"

  # Cleanup files
  rm -rf "${geoip_unzip_folder}"
  rm -f "${input_file}"
  (echo "ASN,Entity"; cat "${input_file}-updated") > "${input_file}"
  rm -f "${input_file}-updated"
}

main() {
  # Declare local variables
  local input_file

  # Initialize local variables
  input_file="${*}"

  # Check if input file variable is set
  if [[ -z "${input_file}" ]]; then
    # Error finding input file
    abort_script "ASN input file error" "Input file not provided!"
  fi

  # Check if input file is not missing
  if [[ ! -f "${input_file}" ]]; then
    # Error missing input file
    abort_script "ASN input file error" "Input file does not exist!"
  fi

  # Check if input file is not empty
  if [[ ! -s "${input_file}" ]]; then
    # Error empty input file
    abort_script "ASN input file error" "Input file is empty!"
  fi

  clean_file "${input_file}"
  update_file "${input_file}"
}

main "${*}"

exit_script "0"

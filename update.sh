#!/bin/bash

abort_script() {
  # Declare local variables
  local script_name

  # Set local variables
  script_name="$(basename "${0}")"

  echo "Aborting ${script_name}"
  for error_msg in "${@}"
  do
      echo "  ${error_msg}"
  done
  exit 1
}

# Format columns and remove unwanted characters
format_file() {
  # Format each individual line
  rm -f "${*}-formatted"
  while read currentLine || [ -n "$currentLine" ]; do
    currentASN="$(echo "${currentLine}" | grep -o -P '^[^,]+' | grep -o -P '[0-9]+')"

    # Check if current line contains an ASN
    if [[ -n "${currentASN}" ]]; then
      currentEntity="$( \
        echo "${currentLine}" \
        | grep -o -P '^\"?[0-9]+\"?,\s*\K.*$' \
        | sed 's/^"\([^"]\)/\1/' \
        | sed 's/["/]\+[^"/]*$//')"
      echo "${currentASN},\"${currentEntity}\"" >> "${*}-formatted"
    fi
  done < "${*}"
  rm -f "${*}"
  (echo "ASN,Entity"; cat "${*}-formatted") > "${*}"
  rm -f "${*}-formatted"
}

# Fix invalid lines, sort, and remove duplicates
clean_file() {
  format_file "${*}"

  rm -f "${*}-cleaned"
  grep -o -P '^\"?[0-9]+\"?,\"?.+\"?$' "${*}" \
    | sort -n -t ',' -k 1,2 \
    | sort -n -u -t ',' -k 1,1 \
    > "${*}-cleaned"
  rm -f "${*}"
  (echo "ASN,Entity"; cat "${*}-cleaned") > "${*}"
  rm -f "${*}-cleaned"
}

check_connectivity() {
  # Declare local variables
  local test_ip
  local test_count

  # Set local variables
  test_count="1"
  if [[ -n "${1}" ]]; then
    test_ip="${1}"
  else
    test_ip="8.8.8.8"
  fi

  # Test connectivity
  if ping -c "${test_count}" "${test_ip}" &> /dev/null; then
    return 0
  else
    return 1
  fi
 }

# Download GeoIP ASN lists
download_geoip_lists() {
  # Declare local variables
  local maxmind_license_key
  local maxmind_file_name

  # Set local variables
  maxmind_license_key=""
  maxmind_file_name="maxmind.ini"

  # Find current MaxMind license key from config file
  if [[ -f "${PWD}/${maxmind_file_name}" ]]; then
    # Found MaxMind config file
    source "${PWD}/${maxmind_file_name}"
  fi

  # Find current MaxMind license key from environment
  if [[ -n "${MAXMIND_LICENSE_KEY}" ]]; then
    # Found MaxMind variable from config file, or in environment
    maxmind_license_key="${MAXMIND_LICENSE_KEY}"
  fi

  # Check if MaxMind license variable is set
  if [[ -z "${maxmind_license_key}" ]]; then
    # Error finding MaxMind license key
    abort_script "MaxMind ASN lists preprocess error" "Failed to find license key!"
  fi

  # Check internet connectivity
  if ! check_connectivity; then
    # Error checking internet connectivity
    abort_script "MaxMind ASN lists preprocess error" "No internet connection!"
  fi

  # Check if MaxMind domain is valid and accessible
  if ! check_connectivity "download.maxmind.com"; then
    # Error checking MaxMind connectivity
    abort_script "MaxMind ASN lists preprocess error" "No connection to MaxMind!"
  fi

  # Download current ASN lists
  rm -f "${*}"
  if ! curl \
    --silent \
    "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN-CSV&license_key=${maxmind_license_key}&suffix=zip" \
    --output "${*}"; then
    # Error downloading ASN lists
    rm -f "${*}"
    abort_script "MaxMind ASN lists download error" "Failed to download!"
  fi

  # Check if downloaded ASN lists is not empty or missing
  if [[ ! -f "${*}" ]]; then
    # Error empty or missing ASN lists
    rm -f "${*}"
    abort_script "MaxMind ASN lists download error" "Download file does not exist!"
  fi

  # Check if downloaded ASN lists is not empty or missing
  if [[ ! -s "${*}" ]]; then
    # Error empty or missing ASN lists
    rm -f "${*}"
    abort_script "MaxMind ASN lists download error" "Download file is empty!"
  fi

  # Check if downloaded ASN lists contains a database error
  if head -1 "${*}" | grep -q "Database edition not found"; then
    # Error invalid MaxMind database
    rm -f "${*}"
    abort_script "MaxMind ASN lists download error" "Database is invalid!"
  fi

  # Check if downloaded ASN lists contains a license error
  if head -1 "${*}" | grep -q "Invalid license key"; then
    # Error invalid MaxMind license key
    rm -f "${*}"
    abort_script "MaxMind ASN lists download error" "License key is invalid!"
  fi

  # Check if downloaded ASN lists contains a suffix error
  if head -1 "${*}" | grep -q "Invalid suffix"; then
    # Error invalid MaxMind suffix
    rm -f "${*}"
    abort_script "MaxMind ASN lists download error" "Suffix is invalid!"
  fi
}

# Update entity names with correct names
update_file() {
  # Declare local variables
  local geoip_file_name

  # Set local variables
  geoip_file_name="GeoLite2-ASN-CSV"

  # Download ASN lists
  download_geoip_lists "${PWD}/${geoip_file_name}.zip"

  # Extract zip file
  rm -rf "${PWD}/${geoip_file_name}"
  mkdir -p "${PWD}/${geoip_file_name}"
  unzip -j \
    -o "${PWD}/${geoip_file_name}.zip" \
    GeoLite2-ASN-CSV_*/* \
    -d "${PWD}/${geoip_file_name}" \
    > /dev/null
  rm -f "${PWD}/${geoip_file_name}.zip"

  # Lookup and format each individual line
  rm -f "${*}-updated"
  while read currentLine || [ -n "$currentLine" ]; do
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
        "${PWD}/${geoip_file_name}/GeoLite2-ASN-Blocks-IPv4.csv" \
        | sed 's/^"\([^"]\)/\1/' \
        | sed 's/["/]\+[^"/]*$//')"
      
      # Check if entity was not set
      if [[ -z "${currentEntity}" ]]; then
        # Find entity in IPv6 GeoIP ASN list
        currentEntity="$( \
          grep -m1 -o -P '^[^,]+,\s*\K'"${currentASN}"',\s*\K.+$' \
          "${PWD}/${geoip_file_name}/GeoLite2-ASN-Blocks-IPv6.csv" \
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
      echo "${currentASN},\"${currentEntity}\"" >> "${*}-updated"
    fi
  done < "${*}"

  # Cleanup files
  rm -rf "${PWD}/${geoip_file_name}"
  rm -f "${*}"
  (echo "ASN,Entity"; cat "${*}-updated") > "${*}"
  rm -f "${*}-updated"
}

main() {
  # Declare local variables
  local input_file

  # Set local variables
  input_file="${*}"

  # Check for input file argument
  if [[ -z "${input_file}" ]]; then
    # Error empty or missing input file argument
    abort_script "Input file argument is empty or does not exist!"
  fi

  clean_file "${input_file}"
  update_file "${input_file}"
}

main "${*}"

exit 0

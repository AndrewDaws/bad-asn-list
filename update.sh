#!/bin/bash
script_name="$(basename "${0}")"

# Format columns and remove unwanted characters
format_file() {
  # Format each individual line
  rm -f "${1}-formatted"
  while read currentLine; do
    currentASN="$(echo "${currentLine}" | grep -o -P '^[^,]+' | grep -o -P '[0-9]+')"

    # Check if current line contains an ASN
    if [[ -n "${currentASN}" ]]; then
      currentEntity="$( \
        echo "${currentLine}" \
        | grep -o -P '^\"?[0-9]+\"?,\s*\K.*$' \
        | sed 's/^"\([^"]\)/\1/' \
        | sed 's/["/]\+[^"/]*$//')"
      echo "${currentASN},\"${currentEntity}\"" >> "${1}-formatted"
    fi
  done < "${1}"
  rm -f "${1}"
  (echo "ASN,Entity"; cat "${1}-formatted") > "${1}"
  rm -f "${1}-formatted"
}

# Fix invalid lines, sort, and remove duplicates
clean_file() {
  rm -f "${1}-cleaned"
  grep -o -P '^\"?[0-9]+\"?,\"?.+\"?$' "${1}" \
    | sort -n -t ',' -k 1,2 \
    | sort -n -u -t ',' -k 1,1 \
    > "${1}-cleaned"
  rm -f "${1}"
  (echo "ASN,Entity"; cat "${1}-cleaned") > "${1}"
  rm -f "${1}-cleaned"
}

# Download GeoIP ASN lists
download_geoip_lists() {
  local maxmind_license_key=""
  local maxmind_file_name="maxmind.ini"

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
    echo "Aborting ${script_name}"
    echo "  Failed to find MaxMind license key!"
    exit 1
  fi

  # Download current GeoIP ASN lists
  rm -f "${*}"
  if ! curl \
    --silent \
    "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN-CSV&license_key=${maxmind_license_key}&suffix=zip" \
    --output "${*}"; then
    # Error downloading GeoIP ASN lists
    rm -f "${*}"
    echo "Aborting ${script_name}"
    echo "  Failed to download current GeoIP ASN lists!"
    exit 1
  fi

  # Check if successfully downloaded GeoIP ASN lists
  if [[ ! -s "${*}" ]]; then
    # Error empty or missing GeoIP ASN lists
    rm -f "${*}"
    echo "Aborting ${script_name}"
    echo "  GeoIP ASN lists from MaxMind is empty or does not exist!"
    exit 1
  fi
}

# Update entity names with correct names
update_file() {
  local geoip_file_name="GeoLite2-ASN-CSV"

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
  while read currentLine; do
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
  local input_file="${*}"

  if [[ -z "${input_file}" ]]; then
    # Error empty or missing input file argument
    echo "Aborting ${script_name}"
    echo "  Input file argument is empty or does not exist!"
    exit 1
  fi

  format_file "${input_file}"
  clean_file "${input_file}"
  update_file "${input_file}"
}

main "${@}"

exit 0

#!/bin/bash
script_name="$(basename "${0}")"

# Download GeoIP ASN lists
download_geoip_lists() {
  # Find current MaxMind license key
  if [[ -z "${MAXMIND_LICENSE_KEY}" ]]; then
    # Error finding MaxMind license key
    echo "Aborting ${script_name}"
    echo "  Failed to find MaxMind license key!"
    exit 1
  fi

  # Download current GeoIP ASN lists
  rm -f "${*}"
  if ! curl \
    --silent \
    "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN-CSV&license_key=${MAXMIND_LICENSE_KEY}&suffix=zip" \
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

  update_file "${input_file}"
}

main "${@}"

exit 0

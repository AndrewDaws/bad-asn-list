#!/bin/bash

# https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN-CSV&license_key=YOUR_LICENSE_KEY&suffix=zip

# Update entity names with correct names
update_file() {
  # Format each individual line
  rm -f "${1}-updated"
  while read currentLine; do
    currentASN="$(echo "${currentLine}" | grep -o -P '^[^,]+' | grep -o -P '[0-9]+')"

    # Check if current line contains an ASN
    if [[ -n "${currentASN}" ]]; then
      currentEntity="$(echo "${currentLine}" | grep -o -P '^\"?[0-9]+\"?,\s*\K.*$' | sed -e 's/"//g')"
      echo "${currentASN},\"${currentEntity}\"" >> "${1}-updated"
    fi
  done < "${1}"
  rm -f "${1}"
  (echo "ASN,Entity"; cat "${1}-updated") > "${1}"
  rm -f "${1}-updated"
}

main() {
  local input_file="${*}"

  update_file "${input_file}"
}

main "${@}"

exit 0

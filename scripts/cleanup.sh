#!/bin/bash

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

main() {
  local input_file="${*}"

  format_file "${input_file}"
  clean_file "${input_file}"
}

main "${@}"

exit 0

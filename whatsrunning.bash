#!/bin/bash

# Function to check if a command is available
command_exists () {
    command -v "$1" >/dev/null 2>&1
}

# Check for required commands
required_commands=("realpath" "ldd" "jq" "grep" "awk" "xargs")
for cmd in "${required_commands[@]}"; do
    if ! command_exists "$cmd"; then
        echo "Error: '$cmd' is not installed. Please install it and try again." >&2
        exit 1
    fi
done

output="[]"
unique_entries=()

while IFS= read -d '' -r proc_folder ; do
	exe="$(realpath -eq "${proc_folder}/exe")"
	if [ -z "$exe" ]; then
		echo "Failed to get exe path for ${proc_folder}" >&2
		continue
	fi

	if ! [ -f "${proc_folder}/maps" ]; then
		echo "Failed to get maps for ${proc_folder}" >&2
		continue
	fi

	planned_libs=$(ldd "$exe" | awk '{print $1}' | sort -u)
	actual_libs=$(grep -e '\.so' "${proc_folder}/maps" | awk '{print $6}' | sort -u | xargs -L1 basename)

	plannedLoaded=()
	plannedNotLoaded=()
	unplannedLoaded=()

	for lib in $planned_libs; do
		if echo "${actual_libs}" | grep -q "$lib"; then
			plannedLoaded+=("$lib")
		else
			plannedNotLoaded+=("$lib")
		fi
	done

	for lib in $actual_libs; do
		if ! echo "${planned_libs}" | grep -q "$lib"; then
			unplannedLoaded+=("$lib")
		fi
	done

	# Create the new JSON object
	new_entry=$(jq -n --arg exe "$exe" \
		--argjson plannedLoaded "$(printf '%s\n' "${plannedLoaded[@]}" | jq -R . | jq -s .)" \
		--argjson plannedNotLoaded "$(printf '%s\n' "${plannedNotLoaded[@]}" | jq -R . | jq -s .)" \
		--argjson unplannedLoaded "$(printf '%s\n' "${unplannedLoaded[@]}" | jq -R . | jq -s .)" \
		'{($exe): {plannedLoaded: $plannedLoaded, plannedNotLoaded: $plannedNotLoaded, unplannedLoaded: $unplannedLoaded}}')

	# Sort the new entry to ensure consistent string comparison
	new_entry_sorted=$(echo "$new_entry" | jq -S .)

	# Check if the new_entry_sorted is already in unique_entries
	duplicate=0
	for entry in "${unique_entries[@]}"; do
		if [ "$entry" == "$new_entry_sorted" ]; then
			duplicate=1
			break
		fi
	done

	# If it's not a duplicate, add it to the output and unique_entries
	if [ $duplicate -eq 0 ]; then
		unique_entries+=("$new_entry_sorted")
		output=$(echo "$output" | jq ". + [$new_entry]")
	fi

done < <(find /proc -mindepth 1 -maxdepth 1 -name '[1-9]*' -print0)

echo "$output" | jq .


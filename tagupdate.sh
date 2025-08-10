#!/bin/bash
# Proxmox LXC/VM Tag Manager (Dynamic LXC OS Tagging)
# ---------------------------------------------------
# Features:
#  - Normalizes tags to semicolon-delimited format (no commas/spaces).
#  - Automatically adds/removes 0_autostart based on onboot setting.
#  - For LXCs: Always tags as 0_lxc_<ostype>, where <ostype> comes from the "ostype:" line in the config.
#    * ostype is lowercased.
#    * If no ostype is found, defaults to 0_lxc_unknown.
#    * Removes any older generic 0_lxc or mismatched LXC tags.
#  - For VMs: Adds 0_vm tag.
#  - Removes empty tags: lines.
# ---------------------------------------------------

add_tag() {
    local cfg="$1" new_tag="$2"
    local tags=$(grep -m1 "^tags:" "$cfg" | cut -d' ' -f2-)
    tags=${tags//[[:space:]]/}   # Remove spaces
    tags=${tags//,/;}            # Convert commas to semicolons

    # If no tags line exists, create one
    if ! grep -q "^tags:" "$cfg"; then
        echo "tags: $new_tag" >> "$cfg"
        echo "Added $new_tag to $(basename "$cfg" .conf)"
        return
    fi

    # Skip if tag already present
    IFS=';' read -ra arr <<< "$tags"
    for t in "${arr[@]}"; do
        [[ "$t" == "$new_tag" ]] && return
    done

    # Append & normalize
    tags="$tags;$new_tag"
    tags=$(echo "$tags" | sed -E 's/;+/;/g; s/^;+//; s/;+$//')
    sed -i "s/^tags:.*/tags: $tags/" "$cfg"
    echo "Appended $new_tag to $(basename "$cfg" .conf)"
}

remove_tag() {
    local cfg="$1" rem_tag="$2"
    local tags=$(grep -m1 "^tags:" "$cfg" | cut -d' ' -f2-)
    [[ -z "$tags" ]] && return
    tags=${tags//[[:space:]]/}
    tags=${tags//,/;}

    if [[ "$tags" =~ (^|;)$rem_tag(;|$) ]]; then
        tags=$(echo "$tags" | sed -E "s/(^|;)$rem_tag(;|$)/;/g")
        tags=$(echo "$tags" | sed -E 's/;+/;/g; s/^;+//; s/;+$//')
        if [[ -z "$tags" ]]; then
            sed -i "/^tags:/d" "$cfg"
        else
            sed -i "s/^tags:.*/tags: $tags/" "$cfg"
        fi
    fi
}

clean_tags() {
    local cfg="$1"
    local tags=$(grep -m1 "^tags:" "$cfg" | cut -d' ' -f2-)
    [[ -z "$tags" ]] && return
    tags=${tags//[[:space:]]/}
    tags=${tags//,/;}
    tags=$(echo "$tags" | sed -E 's/;+/;/g; s/^;+//; s/;+$//')
    if [[ -z "$tags" ]]; then
        sed -i "/^tags:/d" "$cfg"
    else
        sed -i "s/^tags:.*/tags: $tags/" "$cfg"
    fi
}

process_config() {
    local cfg="$1" type_tag="$2"

    # Handle autostart
    if grep -q "^onboot: 1" "$cfg"; then
        add_tag "$cfg" "0_autostart"
    else
        remove_tag "$cfg" "0_autostart"
    fi

    # Apply type-specific tags
    if [[ "$type_tag" == 0_lxc_* ]]; then
        # Remove any old LXC tags before adding new one
        sed -i -E "s/(^tags:.*)(0_lxc_[^;]*)(;|$)/\1\3/g" "$cfg"
        remove_tag "$cfg" "0_lxc"  # remove generic if exists
        add_tag "$cfg" "$type_tag"
    elif [[ "$type_tag" == "0_vm" ]]; then
        add_tag "$cfg" "0_vm"
    fi

    clean_tags "$cfg"
}

echo "=== Processing LXCs ==="
for cfg in /etc/pve/lxc/*.conf; do
    [[ -f "$cfg" ]] || continue
    ostype=$(grep -m1 "^ostype:" "$cfg" | awk '{print tolower($2)}')
    [[ -z "$ostype" ]] && ostype="unknown"
    process_config "$cfg" "0_lxc_${ostype}"
done

echo "=== Processing VMs ==="
for cfg in /etc/pve/qemu-server/*.conf; do
    [[ -f "$cfg" ]] && process_config "$cfg" "0_vm"
done

echo "=== Tagging complete ==="

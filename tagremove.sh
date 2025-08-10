#Tag Remover
#Asks you to select a tag to remove (via prompt)
#Doesn't always works so great

#!/bin/bash



declare -A all_tags=()



# Gather tags from config files, splitting on comma and semicolon

for cfg in /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf; do

  [[ -f "$cfg" ]] || continue

  tags_line=$(grep "^tags:" "$cfg")

  [[ -z "$tags_line" ]] && continue



  tags=$(echo "$tags_line" | cut -d' ' -f2-)



  # Split by comma or semicolon separators

  IFS=',;' read -ra t_arr <<< "$tags"

  for t in "${t_arr[@]}"; do

    t_trimmed=$(echo "$t" | xargs)  # trim whitespace

    if [[ -n "$t_trimmed" ]]; then

      all_tags["$t_trimmed"]=1

    fi

  done

done



if [ ${#all_tags[@]} -eq 0 ]; then

  echo "No tags found on any VM or container."

  exit 0

fi



echo "Tags currently in use:"

select tag_to_remove in "${!all_tags[@]}" "Cancel"; do

  if [[ "$tag_to_remove" == "Cancel" ]]; then

    echo "Canceled by user."

    exit 0

  elif [[ -n "$tag_to_remove" ]]; then

    echo "Selected tag to remove: $tag_to_remove"

    break

  else

    echo "Invalid selection. Please try again."

  fi

done



remove_tag_from_cfg() {

  local cfg=$1

  local vmid=$(basename "$cfg" .conf)

  local tags_line=$(grep "^tags:" "$cfg")

  local tags=$(echo "$tags_line" | cut -d' ' -f2- | tr -d ' ')



  echo "Before: $vmid tags: $tags"



  # Remove the selected tag, matching with optional spaces around separators and tag

  new_tags=$(echo "$tags" | sed -E "s/(^|[,;])\s*$tag_to_remove\s*([,;]|$)/\1\2/g" | sed 's/^[,;]//; s/[,;]$//; s/[,;]{2,}/,/g')



  new_tags=$(echo "$new_tags" | sed 's/^ *//;s/ *$//')  # trim leading/trailing spaces



  if [[ -z "$new_tags" ]]; then

    echo "Removing tags line from $vmid"

    sed -i '/^tags:/d' "$cfg"

  elif [[ "$new_tags" != "$tags" ]]; then

    echo "Updating tags in $vmid to: $new_tags"

    sed -i "s/^tags:.*/tags: $new_tags/" "$cfg"

  else

    echo "No $tag_to_remove tag found in $vmid"

  fi



  # Verify removal

  grep "^tags:" "$cfg" >/dev/null 2>&1 || echo "No tags line in $vmid now"

  if grep "^tags:" "$cfg" | grep -q "$tag_to_remove"; then

    echo "Warning: tag still present in $vmid"

  fi

}



echo "Removing tag '$tag_to_remove' from all configs..."



for cfg in /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf; do

  [[ -f "$cfg" ]] || continue

  # Check if tag is present (consider comma or semicolon separators)

  if grep -qE "^tags:.*([,;]|^)$tag_to_remove([,;]|$)" "$cfg"; then

    remove_tag_from_cfg "$cfg"

  fi

done



echo "Tag removal complete."[/CODE]



Tag "Start at boot" LXCs and VMs with "0_autostart" tag
If onboot: 0, it removes the 0_autostart tag.
If onboot: 1, it adds the 0_autostart tag.
Cleans up commas if the tag is in the middle of a tag list.
Deletes the tags: line entirely if no tags remain.
[CODE=bash]for cfg in /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf; do

  [[ -f "$cfg" ]] || continue

  vmid=$(basename "$cfg" .conf)

  tags=$(grep -m1 "^tags:" "$cfg" | cut -d' ' -f2- | tr -d ' ')

 

  if grep -q "^onboot: 1" "$cfg"; then

    # Ensure tag exists

    if [[ -z "$tags" ]]; then

      echo "Adding tag 0_autostart to $vmid"

      echo "tags: 0_autostart" >> "$cfg"

    elif [[ ! "$tags" =~ (^|,)0_autostart($|,) ]]; then

      echo "Appending tag 0_autostart to $vmid"

      sed -i "s/^tags: \(.*\)/tags: \1,0_autostart/" "$cfg"

    else

      echo "$vmid already has tag 0_autostart"

    fi

  else

    # Remove tag if present

    if [[ "$tags" =~ (^|,)0_autostart($|,) ]]; then

      echo "Removing tag 0_autostart from $vmid"

      newtags=$(echo "$tags" | sed 's/\(,\|^\)0_autostart\(,\|$\)/\1/' | sed 's/^,//;s/,$//;s/,,/,/g')

      if [[ -z "$newtags" ]]; then

        sed -i "/^tags:/d" "$cfg"

      else

        sed -i "s/^tags:.*/tags: $newtags/" "$cfg"

      fi

    else

      echo "$vmid has no 0_autostart tag to remove"

    fi

  fi

done

[/CODE]

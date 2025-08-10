#a single combined script that will loop over all LXC containers, detect their OS, and run the appropriate update commands accordingly (Debian/Ubuntu, Fedora/CentOS/Rocky, Alpine, or skip unknown):

#!/bin/bash
for CT in $(pct list | awk 'NR>1 {print $1}'); do
  OS=$(pct exec $CT -- sh -c "grep '^ID=' /etc/os-release | head -1 | cut -d= -f2" 2>/dev/null | tr -d '"')
  echo "Updating container $CT running $OS..."

  case "$OS" in
    debian|ubuntu)
      pct exec $CT -- bash -c "apt update && apt upgrade -y && apt autoremove -y && apt clean"
      ;;
    fedora|centos|rocky)
      pct exec $CT -- dnf update -y
      ;;
    alpine)
      pct exec $CT -- apk update && apk upgrade
      ;;
    *)
      echo "Unknown or unsupported OS in container $CT, skipping..."
      ;;
  esac
done

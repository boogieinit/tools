#!/bin/bash
# SPDX-License-Identifier: MIT

# This script lists the top 5 CPU, memory, input/output (I/O), and network consuming processes
# This script should work on CentOS, Ubuntu and macOS
#
# Requirements: the script checks for these and exits if any are missing.
# It never installs anything itself; it prints the command you will likely need instead.
#   All systems: ps, sort, head, top
#   Linux:       iotop, iftop, sudo, timeout
#   macOS:       iostat, lsof, netstat

# Detect operating system
if [[ "$OSTYPE" == "darwin"* ]]; then
  OS="macOS"
elif [ -f /etc/centos-release ]; then
  OS="CentOS"
elif [ -f /etc/lsb-release ]; then
  OS="Ubuntu"
else
  OS="Unknown"
fi

echo "Detected OS: $OS"

# Name of the package that provides a program (Linux)
package_for() {
  case "$1" in
    ps|top)            if [[ "$OS" == "CentOS" ]]; then echo "procps-ng"; else echo "procps"; fi ;;
    sort|head|timeout) echo "coreutils" ;;
    *)                 echo "$1" ;;
  esac
}

# Check that the required programs are installed
required="ps sort head top"
if [[ "$OS" == "macOS" ]]; then
  required="$required iostat lsof netstat"
else
  required="$required iotop iftop sudo timeout"
fi

missing=""
for tool in $required; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing="$missing $tool"
  fi
done

if [ -n "$missing" ]; then
  echo "The following required programs are not installed:"
  for tool in $missing; do
    echo "  - $tool"
  done

  # Work out the packages to suggest (no duplicates)
  packages=""
  for tool in $missing; do
    pkg=$(package_for "$tool")
    case " $packages " in
      *" $pkg "*) ;;
      *) packages="$packages $pkg" ;;
    esac
  done

  echo ""
  echo "Please install them, then run this script again. You will likely need to run:"
  case "$OS" in
    CentOS)
      case "$missing" in
        *iotop*|*iftop*) echo "  sudo yum install -y epel-release" ;;
      esac
      echo "  sudo yum install -y$packages"
      ;;
    Ubuntu)
      echo "  sudo apt-get update"
      echo "  sudo apt-get install -y$packages"
      ;;
    macOS)
      echo "  These programs normally come with macOS, so your installation may be incomplete."
      ;;
    *)
      echo "  (unrecognized system) install these with your package manager:$packages"
      ;;
  esac
  exit 1
fi

echo "All required programs are present"

# Function to list top 5 CPU consuming process
list_top_cpu_consuming_processes() {
  # Get the top 5 processes by CPU usage
  top_five_cpu_processes=$(ps -eo pcpu,pid,user,args | sort -k 1 -r | head -n 5)

  # Print the results
  echo "###############################################################################"
  echo "Top 5 CPU consuming processes:"
  echo "$top_five_cpu_processes"
}

# Function to list the top 5 processes by memory usage
list_top_memory_consuming_processes() {
  # Get the top 5 processes by memory usage
  top_five_memory_processes=$(ps -eo pmem,pid,user,args | sort -k 1 -r | head -n 5)

  # Print the results
  echo "###############################################################################"
  echo "Top 5 memory consuming processes:"
  echo "$top_five_memory_processes"
}

# Function to list the top 5 processes by I/O usage
list_top_io_consuming_processes() {
  echo "###############################################################################"
  echo "Top 5 I/O consuming processes:"

  if [[ "$OS" == "macOS" ]]; then
    # macOS has no iotop, so show system-wide disk statistics instead
    echo "Using iostat for I/O statistics (macOS):"
    iostat -d 1 2 | tail -n +4
  else
    # Linux systems
    sudo iotop -o -b -n 1 | head -n 10
  fi
}

# Function to list the top 5 processes by network usage
list_top_network_consuming_processes() {
  echo "###############################################################################"
  echo "Top 5 network consuming processes:"

  if [[ "$OS" == "macOS" ]]; then
    # macOS has no iftop by default, so show connections by process and routes instead
    echo "Network connections by process (macOS):"
    echo "Active network connections:"
    lsof -i -P | head -n 20
    echo ""
    echo "Network statistics:"
    netstat -rn | head -n 10
  else
    # Linux systems
    echo "Running iftop for 5 seconds..."
    timeout 5 sudo iftop -P -n -t 2>/dev/null || echo "iftop requires root privileges and may not work in all environments"
  fi
}

# Main function
main() {
  list_top_cpu_consuming_processes
  list_top_memory_consuming_processes
  list_top_io_consuming_processes
  list_top_network_consuming_processes
}

# Run the main function
main

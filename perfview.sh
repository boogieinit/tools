#!/bin/bash

# This script lists the top 5 CPU, memory, input/output (I/O), and network consuming processes
# This script should work on both CentOS and macOS

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

# Check if top command is present (should be available on all systems by default)
if command -v top >/dev/null 2>&1; then
  echo "top command is present"
else
  echo "top command is not present. This is unusual as top should be available by default."
  exit 1
fi

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

# Check if iotop command is present
if command -v iotop >/dev/null 2>&1; then
  echo "iotop command is present"
else
  echo "iotop command is not present. Installing..."
  case $OS in
    "CentOS")
      sudo yum install -y epel-release
      sudo yum install -y iotop
      ;;
    "Ubuntu")
      sudo apt-get update
      sudo apt-get install -y iotop
      ;;
    "macOS")
      if command -v brew >/dev/null 2>&1; then
        echo "Installing iotop via Homebrew..."
        brew install iotop
      else
        echo "Homebrew not found. Please install Homebrew first or install iotop manually."
        echo "Note: iotop may not work properly on macOS due to security restrictions."
      fi
      ;;
    *)
      echo "Unsupported operating system: $OS"
      echo "Please install iotop manually"
      ;;
  esac
fi

# Function to list the top 5 processes by I/O usage
list_top_io_consuming_processes() {
  echo "###############################################################################"
  echo "Top 5 I/O consuming processes:"
  
  if [[ "$OS" == "macOS" ]]; then
    # On macOS, use fs_usage or iostat as alternatives
    if command -v iostat >/dev/null 2>&1; then
      echo "Using iostat for I/O statistics (macOS):"
      iostat -d 1 2 | tail -n +4
    else
      echo "I/O monitoring tools not available on macOS without additional setup"
      echo "Consider using Activity Monitor or installing monitoring tools via Homebrew"
    fi
  else
    # Linux systems
    if command -v iotop >/dev/null 2>&1; then
      top_five_io_processes=$(sudo iotop -o -b -n 1 | head -n 10)
      echo "$top_five_io_processes"
    else
      echo "iotop not available - please install it first"
    fi
  fi
}

# Check if iftop command is present
if command -v iftop >/dev/null 2>&1; then
  echo "iftop command is present"
else
  echo "iftop command is not present. Installing..."
  case $OS in
    "CentOS")
      sudo yum install -y iftop
      ;;
    "Ubuntu")
      sudo apt-get update
      sudo apt-get install -y iftop
      ;;
    "macOS")
      if command -v brew >/dev/null 2>&1; then
        echo "Installing iftop via Homebrew..."
        brew install iftop
      else
        echo "Homebrew not found. Please install Homebrew first or install iftop manually."
      fi
      ;;
    *)
      echo "Unsupported operating system: $OS"
      echo "Please install iftop manually"
      ;;
  esac
fi


# Function to list the top 5 processes by network usage
list_top_network_consuming_processes() {
  echo "###############################################################################"
  echo "Top 5 network consuming processes:"
  
  if [[ "$OS" == "macOS" ]]; then
    # On macOS, use netstat and lsof as alternatives
    echo "Network connections by process (macOS):"
    if command -v lsof >/dev/null 2>&1; then
      echo "Active network connections:"
      lsof -i -P | head -n 20
    fi
    echo ""
    echo "Network statistics:"
    netstat -rn | head -n 10 2>/dev/null || echo "netstat not available"
  else
    # Linux systems
    if command -v iftop >/dev/null 2>&1; then
      echo "Running iftop for 5 seconds..."
      timeout 5 sudo iftop -P -n -t 2>/dev/null || echo "iftop requires root privileges and may not work in all environments"
    else
      echo "iftop not available - please install it first"
      echo "Alternative: using netstat"
      netstat -tuln | head -n 10 2>/dev/null || echo "netstat not available"
    fi
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

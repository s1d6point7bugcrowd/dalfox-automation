#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

################################################################################
# Spinner Function (Spinning Skull Animation)
################################################################################
spinner() {
  local pid=$1
  local delay=0.2
  # Our "spinning skull" frames
  local spinstr='💀☠🦴👻'
  
  # Hide the cursor
  tput civis
  
  while kill -0 "$pid" 2>/dev/null; do
    for ((i=0; i<${#spinstr}; i++)); do
      echo -ne "\r${CYAN}Scanning in progress...${NC} ${spinstr:$i:1}"
      sleep $delay
    done
  done
  
  # Show the cursor again and clear the spinner line
  tput cnorm
  echo -ne "\r\033[K"
}

################################################################################
# Progress Bar Function
################################################################################
draw_progress_bar() {
  local current=$1
  local total=$2
  local width=40  # width of the progress bar
  local percent=$(( 100 * current / total ))
  local filled=$(( width * current / total ))
  local bar=""
  
  for ((i=1; i<=$filled; i++)); do
    bar="${bar}#"
  done
  while [ ${#bar} -lt $width ]; do
    bar="${bar}-"
  done
  
  echo -ne "${GREEN}[${bar}] ${percent}% (${current}/${total})${NC}\r"
}

################################################################################
# Menu: Choose Domain Mode or Single URL Mode
################################################################################
echo -e "${YELLOW}Choose scanning mode:${NC}"
echo "1) Domain Mode (subdomain enumeration, OOS exclusion, Dalfox scanning)"
echo "2) Single URL Mode (directly scan a single URL with crawling + Dalfox)"
read -p "Enter your choice (1 or 2): " mode_choice

if [[ "$mode_choice" != "1" && "$mode_choice" != "2" ]]; then
  echo -e "${RED}Invalid choice. Exiting.${NC}"
  exit 1
fi

################################################################################
# Prompt for Additional Dalfox Options (Optional, used in both modes)
################################################################################
echo -e "${YELLOW}Enter any additional Dalfox options (flags) you want to use (optional)."
echo -e "For example:"
echo -e "  --cookie 'SESSION=abc123'"
echo -e "  --delay 1000"
echo -e "  -w 20"
echo -e "  --proxy http://127.0.0.1:8080"
echo -e "  --grep ./my_grep.json"
echo -e "Press Enter to skip or if you want default Dalfox behavior.${NC}"
read -p "Dalfox additional options: " dalfox_opts

################################################################################
# Mode 1: Domain Mode
################################################################################
if [ "$mode_choice" = "1" ]; then
    # 1) Prompt for Base Domain
    read -p "Enter the base domain (e.g., example.com): " base_domain
    if [ -z "$base_domain" ]; then
        echo -e "${RED}Base domain cannot be empty!${NC}"
        exit 1
    fi

    # 2) Prompt for Comma-Separated OOS (Out of Scope) Items
    echo -e "${YELLOW}If you have any OOS items, enter them comma-separated."
    echo -e "(e.g., out1.com,out2.com). Press Enter to skip.${NC}"
    read -p "OOS (comma-separated): " oos_input

    # Create a temporary exclude file based on the user's OOS input
    exclude_file=$(mktemp)
    if [ -n "$oos_input" ]; then
        IFS=',' read -ra oos_array <<< "$oos_input"
        for item in "${oos_array[@]}"; do
            trimmed_item=$(echo "$item" | xargs)
            echo "$trimmed_item" >> "$exclude_file"
        done
        echo -e "${CYAN}Created an exclude file with these OOS entries:${NC}"
        cat "$exclude_file"
    fi

    # 3) Create Temporary Files
    echo -e "${CYAN}Creating temporary files for processing...${NC}"
    subdomains_file=$(mktemp)
    excluded_subdomains_file=$(mktemp)
    live_subdomains_file=$(mktemp)

    # 4) Subdomain Enumeration (subfinder)
    echo -e "${GREEN}Finding subdomains (using subfinder)...${NC}"
    subfinder -d "$base_domain" -silent > "$subdomains_file"

    if [ ! -s "$subdomains_file" ]; then
        echo -e "${RED}No subdomains found for the given base domain!${NC}"
        rm -f "$subdomains_file" "$excluded_subdomains_file" "$live_subdomains_file" "$exclude_file"
        exit 1
    fi

    # 5) Exclude OOS Items
    echo -e "${YELLOW}Excluding out-of-scope items (if any)...${NC}"
    if [ -f "$exclude_file" ] && [ -s "$exclude_file" ]; then
        grep -F -v -f "$exclude_file" "$subdomains_file" > "$excluded_subdomains_file"
    else
        cp "$subdomains_file" "$excluded_subdomains_file"
    fi

    if [ ! -s "$excluded_subdomains_file" ]; then
        echo -e "${RED}All subdomains were excluded! Nothing to scan.${NC}"
        rm -f "$subdomains_file" "$excluded_subdomains_file" "$live_subdomains_file" "$exclude_file"
        exit 1
    fi

    # 6) Probing for Live Subdomains (httpx)
    echo -e "${GREEN}Probing for live subdomains (httpx)...${NC}"
    httpx -silent -mc 200 -l "$excluded_subdomains_file" -o "$live_subdomains_file"

    if [ ! -s "$live_subdomains_file" ]; then
        echo -e "${RED}No live subdomains found after exclusion!${NC}"
        rm -f "$subdomains_file" "$excluded_subdomains_file" "$live_subdomains_file" "$exclude_file"
        exit 1
    fi

    # 7) Show Discovered Live Subdomains
    echo -e "${BLUE}\nThe following subdomains are live (HTTP 200):${NC}"
    cat "$live_subdomains_file"

    echo -e "${BLUE}\nWe will now scan each subdomain in turn."
    echo -e "After each subdomain is done, you'll be asked if you want to continue.${NC}"

    # This file will collect final results for all subdomains
    final_result="result.txt"
    > "$final_result"  # Clear or initialize the file

    # Count how many subdomains total
    sub_count=0
    total_subdomains=$(wc -l < "$live_subdomains_file")

    # Loop each live subdomain
    while read -r subdomain; do
        sub_count=$(( sub_count + 1 ))
        
        # Show a progress bar for subdomain index
        echo -e "\n${YELLOW}Scanning subdomain [$sub_count/$total_subdomains]: $subdomain${NC}"
        draw_progress_bar "$sub_count" "$total_subdomains"
        echo ""
        
        # === BEGIN SUBDOMAIN SCAN STEPS ===
        # (8a) Create temp files for subdomain scanning
        temp_urls=$(mktemp)
        temp_urls_filtered=$(mktemp)

        # (8b) Crawl with Gospider (run in background + spinner)
        echo -e "${BLUE}Crawling $subdomain with Gospider...${NC}"
        gospider -u "$subdomain" -c 7 -d 5 \
          --blacklist ".(jpg|jpeg|gif|css|tif|tiff|png|ttf|woff|woff2|ico|pdf|svg|txt)" \
          --other-source \
          | grep -e "code-200" \
          | awk '{print $5}' \
          > "$temp_urls" &
        gos_pid=$!
        spinner "$gos_pid"
        wait "$gos_pid"

        # (8c) Filter with gf xss
        echo -e "${BLUE}Filtering URLs for potential XSS (gf xss)...${NC}"
        cat "$temp_urls" | gf xss > "$temp_urls_filtered"

        # (8d) XSS Scanning with Dalfox (pipe mode) + spinner
        echo -e "${MAGENTA}Running Dalfox pipe mode on $subdomain...${NC}"
        cat "$temp_urls_filtered" | dalfox pipe $dalfox_opts >> "$final_result" 2>&1 &
        dal_pid=$!
        spinner "$dal_pid"
        wait "$dal_pid"

        # (8e) Cleanup subdomain temp files
        rm -f "$temp_urls" "$temp_urls_filtered"

        echo -e "${GREEN}Finished scanning $subdomain. Results appended to $final_result${NC}"
        # === END SUBDOMAIN SCAN STEPS ===
        
        # Ask if we should continue with the next subdomain
        if [ "$sub_count" -lt "$total_subdomains" ]; then
            echo -e "${YELLOW}\nContinue to the next subdomain? (y/n)${NC}"
            read -p "[y/n]: " continue_ans
            continue_ans=${continue_ans:-y}  # default to yes
            if [[ ! "$continue_ans" =~ ^[Yy]$ ]]; then
                echo -e "${CYAN}Stopping subdomain scanning early.${NC}"
                break
            fi
        fi
    done < "$live_subdomains_file"

    # Cleanup domain mode files
    rm -f "$subdomains_file" "$excluded_subdomains_file" "$live_subdomains_file" "$exclude_file"

    echo -e "${GREEN}\nDomain Mode completed. Consolidated results saved to $final_result${NC}"
    exit 0
fi

################################################################################
# Mode 2: Single URL Mode
################################################################################
if [ "$mode_choice" = "2" ]; then
    # 1) Prompt for Single URL
    read -p "Enter a single URL (e.g., https://www.example.com): " single_url
    if [ -z "$single_url" ]; then
        echo -e "${RED}URL cannot be empty!${NC}"
        exit 1
    fi

    # 2) Temporary Files
    echo -e "${CYAN}Creating temporary files for processing...${NC}"
    temp_urls=$(mktemp)
    temp_urls_filtered=$(mktemp)

    # 3) Crawl the Single URL with Gospider + spinner
    echo -e "${BLUE}Crawling the single URL with Gospider...${NC}"
    gospider -u "$single_url" -c 5 -d 2 \
        --blacklist ".(jpg|jpeg|gif|css|tif|tiff|png|ttf|woff|woff2|ico|pdf|svg|txt)" \
        --other-source \
        | grep -e "code-200" \
        | awk '{print $5}' \
        > "$temp_urls" &
    gos_pid=$!
    spinner "$gos_pid"
    wait "$gos_pid"

    # 4) Filter Potential XSS Endpoints (gf xss)
    echo -e "${BLUE}Filtering URLs for potential XSS parameters (gf xss)...${NC}"
    cat "$temp_urls" | gf xss > "$temp_urls_filtered"

    # 5) XSS Scanning with Dalfox in Pipe Mode + spinner
    echo -e "${MAGENTA}Scanning for XSS (dalfox pipe mode)...${NC}"
    cat "$temp_urls_filtered" | dalfox pipe $dalfox_opts | tee result.txt &
    dal_pid=$!
    spinner "$dal_pid"
    wait "$dal_pid"

    # 6) Optional: Direct Single-URL Analysis with Dalfox "url" Mode + spinner
    echo -e "${MAGENTA}Also scanning the main URL with 'dalfox url'...${NC}"
    dalfox url "$single_url" $dalfox_opts | tee -a result.txt &
    dal2_pid=$!
    spinner "$dal2_pid"
    wait "$dal2_pid"

    # 7) Cleanup
    echo -e "${CYAN}Cleaning up temporary files...${NC}"
    rm -f "$temp_urls" "$temp_urls_filtered"

    echo -e "${GREEN}Single URL Mode completed. Results saved to result.txt${NC}"
    exit 0
fi

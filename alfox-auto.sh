#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Prompt the user for the base domain
read -p "Enter the base domain (e.g., example.com): " base_domain

# Check if the base domain is empty
if [ -z "$base_domain" ]; then
    echo -e "${RED}Base domain cannot be empty!${NC}"
    exit 1
fi

echo -e "${CYAN}Creating temporary files...${NC}"
# Create temporary files for storing intermediate results
subdomains_file=$(mktemp)
clean_urls_file=$(mktemp)
temp_urls=$(mktemp)
temp_urls_filtered=$(mktemp)

echo -e "${GREEN}Finding subdomains and probing for live URLs...${NC}"
# Use subfinder to find subdomains and httpx to probe for live URLs
subfinder -d "$base_domain" -silent | httpx -silent -mc 200 -o "$subdomains_file"

# Check if any subdomains were found
if [ ! -s "$subdomains_file" ]; then
    echo -e "${RED}No live subdomains found for the given base domain!${NC}"
    rm "$subdomains_file" "$clean_urls_file" "$temp_urls" "$temp_urls_filtered"
    exit 1
fi

echo -e "${YELLOW}Extracting URLs from subdomains...${NC}"
# Extract just the URLs without status codes
awk '{print $1}' "$subdomains_file" > "$clean_urls_file"

echo -e "${BLUE}Gathering URLs from subdomains using gospider...${NC}"
# Run gospider to gather URLs from the discovered subdomains
gospider -S "$clean_urls_file" -c 7 -d 5 \
    --blacklist ".(jpg|jpeg|gif|css|tif|tiff|png|ttf|woff|woff2|ico|pdf|svg|txt)" \
    --other-source \
    | grep -e "code-200" \
    | awk '{print $5}' \
    | gf xss \
    > "$temp_urls"

echo -e "${BLUE}Filtering URLs with gf xss...${NC}"
# Filter URLs using gf xss to potentially identify more relevant targets
cat "$temp_urls" | gf xss > "$temp_urls_filtered" 

echo -e "${MAGENTA}Scanning for XSS with dalfox...${NC}"
# Run dalfox with rate limiting and worker threads
cat "$temp_urls_filtered" | dalfox pipe --delay 200 --waf-evasion --worker 5 | tee result.txt

echo -e "${CYAN}Cleaning up temporary files...${NC}"
# Cleanup temporary files
rm "$subdomains_file" "$clean_urls_file" "$temp_urls" "$temp_urls_filtered"

echo -e "${GREEN}The results have been saved to result.txt${NC}"

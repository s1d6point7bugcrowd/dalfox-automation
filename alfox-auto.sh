#!/bin/bash

# Prompt the user to enter the base domain
read -p "Enter the base domain (e.g., example.com): " base_domain

# Check if the base domain is empty
if [ -z "$base_domain" ]; then
    echo "Base domain cannot be empty!"
    exit 1
fi

# Create a temporary file to store subdomains and another for intermediate results
subdomains_file=$(mktemp)
clean_urls_file=$(mktemp)
temp_urls=$(mktemp)

# Use subfinder to find subdomains and httpx to probe for live URLs
subfinder -d "$base_domain" -silent | httpx -silent -mc 200 -o "$subdomains_file"

# Check if any subdomains were found
if [ ! -s "$subdomains_file" ]; then
    echo "No live subdomains found for the given base domain!"
    rm "$subdomains_file" "$clean_urls_file" "$temp_urls"
    exit 1
fi

# Extract just the URLs without status codes
awk '{print $1}' "$subdomains_file" > "$clean_urls_file"

# Run gospider to gather URLs from the discovered subdomains
gospider -S "$clean_urls_file" -c 10 -d 5 --blacklist ".(jpg|jpeg|gif|css|tif|tiff|png|ttf|woff|woff2|ico|pdf|svg|txt)" --other-source \
    | grep -e "code-200" \
    | awk '{print $5}' \
    | grep "=" \
    | gf xss \
    > "$temp_urls"

# Replace query string values with qsreplace and run dalfox
cat "$temp_urls" | qsreplace -a | dalfox pipe | tee result.txt

# Cleanup temporary files
rm "$subdomains_file" "$clean_urls_file" "$temp_urls"

echo "The results have been saved to result.txt"

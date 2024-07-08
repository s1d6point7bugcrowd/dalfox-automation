# Dalfox Auto Scanner Script

This script automates the process of discovering and scanning URLs for XSS vulnerabilities using a combination of `subfinder`, `httpx`, `gospider`, `gf`, `qsreplace`, and `dalfox`.

## Prerequisites

Make sure you have the following tools installed on your system:

https://github.com/1ndianl33t/Gf-Patterns

- `subfinder`
- `httpx`
- `gospider`
- `gf`
- `qsreplace`
- `dalfox`

You can install these tools using `go get` or the respective package manager for your operating system.

### Installing Prerequisites


```sh
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest

go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest

go install github.com/jaeles-project/gospider@latest

go install github.com/tomnomnom/gf@latest

go install github.com/tomnomnom/qsreplace@latest

go install github.com/hahwul/dalfox/v2@latest



save the script below as dalfox-auto.sh.
Make the script executable: chmod +x dalfox-auto.sh.
Run the script: ./dalfox-auto.sh.


****To respect a rate limit of no more than 5 requests per second, you need to set appropriate delays and adjust the worker count in the script. We can use dalfox's --delay option to introduce a delay between requests.****  eg: dalfox pipe --delay 200 --worker 5 | tee result.txt (This is not set as default)



Explanation

    Prompt for Base Domain: The script prompts the user to enter a base domain.
    Check for Empty Input: It checks if the base domain input is empty and exits with an error if it is.
    Temporary Files Creation: Creates temporary files to store subdomains, clean URLs, and intermediate results.
    Subdomain Discovery and Probing: Uses subfinder to discover subdomains and httpx to probe for live URLs, saving the results to a temporary file.
    Live Subdomains Check: Checks if any live subdomains were found. If not, it cleans up and exits with an error message.
    Extract URLs Without Status Codes: Uses awk to extract only the URLs from the httpx output, discarding status codes.
    gospider Execution: Runs gospider on the cleaned URLs, filters for "code-200" responses, extracts URLs containing =, and further filters using gf xss.
    qsreplace and dalfox Execution: Replaces query string values using qsreplace and pipes the result to dalfox for scanning, saving the output to result.txt.
    Cleanup: Removes temporary files and informs the user that the results are saved.

Output

The script saves the results of the Dalfox scan to a file named result.txt in the current directory.







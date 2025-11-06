#!/bin/bash

# API Key Leak Detection Script
# Scans codebase for potential exposed API keys and secrets
# Usage: ./check_api_keys.sh [directory]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default to current directory if no argument provided
SCAN_DIR="${1:-.}"

# Output file for detailed results
OUTPUT_FILE="api_key_scan_results.txt"

# Counter for findings
TOTAL_FINDINGS=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}API Key & Secret Leak Detection Scanner${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Scanning directory: ${GREEN}$SCAN_DIR${NC}"
echo ""

# Create/clear output file
> "$OUTPUT_FILE"

# Function to check for patterns and report findings
check_pattern() {
    local pattern="$1"
    local description="$2"
    local severity="$3"

    echo -e "${BLUE}Checking for: ${NC}$description"

    # Search for pattern, excluding certain directories and files
    local results=$(grep -rniE "$pattern" "$SCAN_DIR" \
        --exclude-dir={node_modules,.git,build,DerivedData,Pods,.build,vendor,dist,out} \
        --exclude="*.{log,lock,sum,mod,jar,png,jpg,jpeg,gif,ico,svg,woff,woff2,ttf,eot,pdf,zip,tar,gz}" \
        --exclude="check_api_keys.sh" \
        --exclude="$OUTPUT_FILE" \
        2>/dev/null || true)

    if [ -n "$results" ]; then
        local count=$(echo "$results" | wc -l | tr -d ' ')
        TOTAL_FINDINGS=$((TOTAL_FINDINGS + count))

        if [ "$severity" = "HIGH" ]; then
            echo -e "  ${RED}[HIGH] Found $count potential leak(s)${NC}"
        elif [ "$severity" = "MEDIUM" ]; then
            echo -e "  ${YELLOW}[MEDIUM] Found $count potential leak(s)${NC}"
        else
            echo -e "  ${YELLOW}[LOW] Found $count potential leak(s)${NC}"
        fi

        echo "" >> "$OUTPUT_FILE"
        echo "========================================" >> "$OUTPUT_FILE"
        echo "$description ($severity SEVERITY)" >> "$OUTPUT_FILE"
        echo "========================================" >> "$OUTPUT_FILE"
        echo "$results" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    else
        echo -e "  ${GREEN}✓ No issues found${NC}"
    fi
}

echo ""
echo -e "${BLUE}Starting security scan...${NC}"
echo ""

# OpenAI API Keys
check_pattern 'sk-[a-zA-Z0-9]{48}' "OpenAI API Keys" "HIGH"

# OpenAI Project/Organization Keys
check_pattern 'sk-proj-[a-zA-Z0-9_-]{48,}' "OpenAI Project Keys" "HIGH"

# Anthropic Claude API Keys
check_pattern 'sk-ant-api[0-9]{2}-[a-zA-Z0-9_-]{95,}' "Anthropic Claude API Keys" "HIGH"

# Google API Keys
check_pattern 'AIza[0-9A-Za-z_-]{35}' "Google API Keys" "HIGH"

# GitHub Personal Access Tokens
check_pattern 'ghp_[a-zA-Z0-9]{36}' "GitHub Personal Access Tokens" "HIGH"
check_pattern 'gho_[a-zA-Z0-9]{36}' "GitHub OAuth Tokens" "HIGH"
check_pattern 'ghu_[a-zA-Z0-9]{36}' "GitHub User-to-Server Tokens" "HIGH"
check_pattern 'ghs_[a-zA-Z0-9]{36}' "GitHub Server-to-Server Tokens" "HIGH"
check_pattern 'ghr_[a-zA-Z0-9]{36}' "GitHub Refresh Tokens" "HIGH"

# AWS Keys
check_pattern 'AKIA[0-9A-Z]{16}' "AWS Access Key IDs" "HIGH"
check_pattern 'aws_secret_access_key\s*=\s*[A-Za-z0-9/+=]{40}' "AWS Secret Access Keys" "HIGH"

# Stripe API Keys
check_pattern 'sk_live_[0-9a-zA-Z]{24,}' "Stripe Live Secret Keys" "HIGH"
check_pattern 'rk_live_[0-9a-zA-Z]{24,}' "Stripe Live Restricted Keys" "HIGH"
check_pattern 'sk_test_[0-9a-zA-Z]{24,}' "Stripe Test Secret Keys" "MEDIUM"

# Slack Tokens
check_pattern 'xox[pbar]-[0-9]{10,12}-[0-9]{10,12}-[a-zA-Z0-9]{24,}' "Slack Tokens" "HIGH"

# Twilio API Keys
check_pattern 'SK[a-z0-9]{32}' "Twilio API Keys" "HIGH"

# SendGrid API Keys
check_pattern 'SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}' "SendGrid API Keys" "HIGH"

# MailChimp API Keys
check_pattern '[0-9a-f]{32}-us[0-9]{1,2}' "MailChimp API Keys" "HIGH"

# Hugging Face API Tokens
check_pattern 'hf_[a-zA-Z0-9]{34,}' "Hugging Face API Tokens" "HIGH"

# Generic API Key patterns in code
check_pattern '(api[_-]?key|apikey)\s*[:=]\s*["\x27][a-zA-Z0-9_-]{20,}["\x27]' "Generic API Keys in Code" "MEDIUM"
check_pattern '(secret[_-]?key|secretkey)\s*[:=]\s*["\x27][a-zA-Z0-9_-]{20,}["\x27]' "Generic Secret Keys in Code" "MEDIUM"
check_pattern '(access[_-]?token|accesstoken)\s*[:=]\s*["\x27][a-zA-Z0-9_-]{20,}["\x27]' "Generic Access Tokens in Code" "MEDIUM"

# Bearer tokens
check_pattern 'Bearer\s+[a-zA-Z0-9_-]{20,}' "Bearer Tokens" "MEDIUM"

# Authorization headers with tokens
check_pattern 'Authorization:\s*(Bearer|Token)\s+[a-zA-Z0-9_-]{20,}' "Authorization Headers" "MEDIUM"

# Private keys
check_pattern '-----BEGIN (RSA |DSA |EC )?PRIVATE KEY-----' "Private Keys (PEM Format)" "HIGH"

# SSH private keys
check_pattern '-----BEGIN OPENSSH PRIVATE KEY-----' "SSH Private Keys" "HIGH"

# JWT tokens (only check for complete tokens, not just format)
check_pattern 'eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}' "JWT Tokens" "MEDIUM"

# Password in plain text (common patterns)
check_pattern '(password|passwd|pwd)\s*[:=]\s*["\x27][^"\x27]{8,}["\x27]' "Hardcoded Passwords" "MEDIUM"

# Database connection strings
check_pattern '(mongodb|postgres|mysql|redis)://[^:]+:[^@]+@' "Database Connection Strings with Credentials" "HIGH"

# .env file exposure check
if [ -f "$SCAN_DIR/.env" ]; then
    echo -e "${RED}WARNING: .env file found in repository!${NC}"
    TOTAL_FINDINGS=$((TOTAL_FINDINGS + 1))
    echo "" >> "$OUTPUT_FILE"
    echo "========================================" >> "$OUTPUT_FILE"
    echo ".env FILE FOUND (HIGH SEVERITY)" >> "$OUTPUT_FILE"
    echo "========================================" >> "$OUTPUT_FILE"
    echo "Path: $SCAN_DIR/.env" >> "$OUTPUT_FILE"
    echo "This file should be in .gitignore and not committed!" >> "$OUTPUT_FILE"
fi

# Check for credentials.json or similar files
find "$SCAN_DIR" -type f \( -name "credentials.json" -o -name "secrets.json" -o -name "config.secret.*" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/build/*" 2>/dev/null | while read -r file; do
    echo -e "${YELLOW}WARNING: Potential secrets file found: $file${NC}"
    TOTAL_FINDINGS=$((TOTAL_FINDINGS + 1))
    echo "" >> "$OUTPUT_FILE"
    echo "Potential secrets file: $file" >> "$OUTPUT_FILE"
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Scan Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ $TOTAL_FINDINGS -eq 0 ]; then
    echo -e "${GREEN}✓ No API keys or secrets detected!${NC}"
    echo -e "${GREEN}Your codebase appears to be clean.${NC}"
    rm -f "$OUTPUT_FILE"
else
    echo -e "${RED}⚠ Found $TOTAL_FINDINGS potential issue(s)${NC}"
    echo ""
    echo -e "Detailed results saved to: ${YELLOW}$OUTPUT_FILE${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT NOTES:${NC}"
    echo "1. Review each finding to determine if it's a real leak"
    echo "2. Some findings may be false positives (e.g., example keys, test data)"
    echo "3. If real keys are found:"
    echo "   - Immediately revoke/rotate the exposed keys"
    echo "   - Remove them from git history using git-filter-repo or BFG"
    echo "   - Add them to .gitignore"
    echo "   - Use environment variables or secure secret management instead"
    echo ""
    echo -e "${YELLOW}Recommended Actions:${NC}"
    echo "- Review: cat $OUTPUT_FILE"
    echo "- Clean git history: git filter-repo --path <file> --invert-paths"
    echo "- Use git-secrets: https://github.com/awslabs/git-secrets"
fi

echo ""

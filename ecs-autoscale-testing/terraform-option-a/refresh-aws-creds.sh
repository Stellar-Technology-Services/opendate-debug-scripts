#!/bin/bash
# Script to refresh AWS credentials from current AWS CLI session
# Updates ~/.aws/credentials with current temporary credentials

set -e

echo "Refreshing AWS credentials..."

# Backup and remove expired credentials file so AWS CLI reads from current session
CREDENTIALS_FILE="$HOME/.aws/credentials"
if [ -f "$CREDENTIALS_FILE" ]; then
    echo "Backing up existing credentials file..."
    cp "$CREDENTIALS_FILE" "${CREDENTIALS_FILE}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    echo "Removing expired credentials file to force reading from current session..."
    rm -f "$CREDENTIALS_FILE"
fi

# Also remove any temporary credentials files
if [ -f "${CREDENTIALS_FILE}.tmp" ]; then
    rm -f "${CREDENTIALS_FILE}.tmp"
fi

# Export credentials and extract values (strip any trailing carriage returns)
# Now this will read from SSO cache or environment variables instead of expired file
AWS_ACCESS_KEY_ID=$(aws configure export-credentials --format env 2>/dev/null | grep '^export AWS_ACCESS_KEY_ID=' | cut -d'=' -f2 | tr -d '\r')
AWS_SECRET_ACCESS_KEY=$(aws configure export-credentials --format env 2>/dev/null | grep '^export AWS_SECRET_ACCESS_KEY=' | cut -d'=' -f2 | tr -d '\r')
AWS_SESSION_TOKEN=$(aws configure export-credentials --format env 2>/dev/null | grep '^export AWS_SESSION_TOKEN=' | cut -d'=' -f2 | tr -d '\r')

# Check if credentials were retrieved
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
    echo "Error: Failed to retrieve AWS credentials. Make sure you're logged in via AWS CLI." >&2
    exit 1
fi

# Ensure ~/.aws directory exists
mkdir -p ~/.aws

# Write credentials file
cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
aws_session_token = ${AWS_SESSION_TOKEN}
EOF

echo "Credentials successfully refreshed!"
echo "Credentials file location: ~/.aws/credentials"

# Show expiration time if available
EXPIRATION=$(aws configure export-credentials --format env 2>/dev/null | grep '^export AWS_CREDENTIAL_EXPIRATION=' | cut -d'=' -f2 | tr -d '\r')
if [ -n "$EXPIRATION" ]; then
    echo "Credentials expire at: ${EXPIRATION}"
fi

# Display account/environment information
echo ""
echo "=== AWS Account/Environment Information ==="
CALLER_IDENTITY=$(aws sts get-caller-identity 2>/dev/null)
if [ $? -eq 0 ]; then
    ACCOUNT=$(echo "$CALLER_IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
    ARN=$(echo "$CALLER_IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
    USER_ID=$(echo "$CALLER_IDENTITY" | grep -o '"UserId": "[^"]*' | cut -d'"' -f4)
    
    REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    echo "Account ID: ${ACCOUNT}"
    echo "Region: ${REGION}"
    echo "ARN: ${ARN}"
    echo "User ID: ${USER_ID}"
    
    # Extract role name and session name if it's an assumed role
    if echo "$ARN" | grep -q "assumed-role"; then
        ROLE_NAME=$(echo "$ARN" | sed -n 's/.*assumed-role\/\([^/]*\)\/.*/\1/p')
        SESSION_NAME=$(echo "$ARN" | sed -n 's/.*assumed-role\/[^/]*\/\(.*\)/\1/p')
        echo "Role: ${ROLE_NAME}"
        echo "Session: ${SESSION_NAME}"
    fi
else
    echo "Warning: Could not retrieve caller identity. Credentials may not be valid yet."
fi
echo "=========================================="

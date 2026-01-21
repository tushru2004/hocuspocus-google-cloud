#!/bin/bash
#
# Create a standard (non-admin) user account on macOS
# This script is designed to be run via SimpleMDM
#

set -e

# User configuration - change these values as needed
USERNAME="restricted"
FULLNAME="Restricted"
PASSWORD="changeme123"  # User should change this after first login

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists"
    exit 0
fi

# Create the standard user using sysadminctl
# -addUser: creates the user
# -fullName: display name
# -password: initial password
# -home: home directory path
# No -admin flag = standard user (not admin)
sysadminctl -addUser "$USERNAME" \
    -fullName "$FULLNAME" \
    -password "$PASSWORD" \
    -home "/Users/$USERNAME"

# Verify user was created
if id "$USERNAME" &>/dev/null; then
    echo "Successfully created standard user: $USERNAME"

    # Verify user is NOT an admin
    if dseditgroup -o checkmember -m "$USERNAME" admin &>/dev/null; then
        echo "WARNING: User is an admin - this should not happen"
        exit 1
    else
        echo "Confirmed: $USERNAME is a standard (non-admin) user"
    fi
else
    echo "Failed to create user"
    exit 1
fi

echo "Done. User can log in with password: $PASSWORD"
echo "Recommend changing password after first login."

#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# MIT License
#
# Copyright (c) 2024 Alton Brailovskiy
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

jamfProURL="$4"
client_id="$5"
client_secret="$6"
staticGroupID="$7"  

# Local Testing Variables
#jamfProURL="https://URL.jamfcloud.com"
#client_id='<client_id_Here>'
#client_secret='<client_secret_Here>'
#staticGroupID="<staticGroupID_Here>"

# Obtain the bearer token
BearerTokenResponse=$(curl --location --request POST "${jamfProURL}/api/oauth/token" \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${client_id}" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_secret=${client_secret}")

access_token=$(echo "$BearerTokenResponse" | awk -F'"access_token":"' '{print $2}' | awk -F'"' '{print $1}')
#echo access_token: $access_token
bearerToken=$(echo "$access_token")
#echo bearerToken: $bearerToken

if [[ -n "$bearerToken" ]]; then
    echo "Bearer token: Successfully Stored."
elif [[ -z "$bearerToken" ]]; then
    echo "Authentication failed. Check credentials or endpoint."
    exit 1
fi

# Get the computer ID using the serial number
serialNumber=$(system_profiler SPHardwareDataType | awk '/Serial/ {print $NF}')
jamfProID=$(curl -ks -H "Authorization: Bearer ${bearerToken}" "$jamfProURL/JSSResource/computers/serialnumber/$serialNumber" | xpath -e "//computer/general/id/text()")
echo jamf pro id: $jamfProID

# Check if the computer ID is obtained successfully
if [ -n "$jamfProID" ]; then
    #Bearer Auth Support
curl -ks -H "Authorization: Bearer ${bearerToken}" -X PUT "$jamfProURL/JSSResource/computergroups/id/$staticGroupID" \
    -H "Content-Type: text/xml" \
    -d "<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer_group><computer_deletions><computer><id>$jamfProID</id></computer></computer_deletions></computer_group>"

echo "Computer deleted from static group with ID $staticGroupID"

else
    echo "Failed to retrieve Jamf Pro ID. Computer not removed from static group."
    exit 1
fi

# Invalidate the bearer token with retry logic
while true; do
    responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" "$jamfProURL/api/v1/auth/invalidate-token" -X POST -s -o /dev/null)
    echo "Response Code: $responseCode"
    
    if [[ ${responseCode} -eq 204 ]]; then
        echo "Token successfully invalidated."
        bearerToken=""
        echo "Exiting script..."
        exit 0
        
    elif [[ ${responseCode} -eq 401 ]]; then
        echo "Token already invalid."
        echo "Exiting script..."
        exit 0
        
    else
        echo "An unknown error occurred invalidating the token."
        
        retryCount=$((retryCount + 1))
        if [[ ${retryCount} -ge ${maxRetries} ]]; then
            echo "Maximum retries reached. Exiting script..."
            exit 1
        fi
        
        echo "Retrying in ${retryInterval} seconds..."
        sleep ${retryInterval}
    fi
done

exit 0

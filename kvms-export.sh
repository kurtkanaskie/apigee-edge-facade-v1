#!/bin/bash

# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Works on GNU bash, version 3.2.57(1)-release (x86_64-apple-darwin20)
# Author: Kurt Kanaskie, Google (kurtkanaskie@google.com)
# Updated: 2024-12-02

Help()
{
   # Display Help
   echo
   echo "Export KVMs and entries including encrypted entries."
   echo "Output format for Edge or X (suitable for import to X with apigeecli)"
   echo "Uses environment variables for ORG, ENVS and B64UNPW if set."
   echo
   echo "Syntax: $0 [-h|-e|-o|-b|-f|-x"
   echo "options:"
   echo "    -h    Print this help"
   echo "    -b    Base 64 encoded username:password"
   echo "    -e    Environment name(s) space separated, if empty all envronments are exported"
   echo "    -f    Output format [ edge | X (default) ]"
   echo "    -o    Organization name"
   echo "    -x    Export output dir"
   echo
   echo "Usage:      $0 -b B64UNPW -o ORG, and -x OUTPUT_DIR options or environment variables are required."
   echo
   echo "Usage X:    $0 -x edge-export -f Edge"
   echo "Usage Edge: $0 -x x-import -f X"

   echo
}

while getopts "b:e:f:o:x:h" flag
do
    case "${flag}" in
        h) Help
            exit;;
        e) ENVS=${OPTARG};;
        o) ORG=${OPTARG};;
        b) B64UNPW=${OPTARG};;
        f) FORMAT=${OPTARG};;
        x) OUTPUT_DIR=${OPTARG};;
        \?) # Invalid option
            echo "Error: Invalid option"
            Help
        exit;;
    esac
done

if [[ "$ORG" == "" || "$OUTPUT_DIR" == "" || "$B64UNPW" == "" ]]
then
    echo
    echo "ERROR: -b B64UNPW -o ORG, and -x OUTPUT_DIR options or environment variables are required."
    Help
    exit
fi

# Psuedo code
: '
mkdir -p $OUTPUT_DIR
GET KVMs for org
  for each KVM
    GET KVM to check for encrpted 
    GET KEMV keys
    GET first key by rewriting the KV-decrypt-entry policy for the org and map name
    GET subsequent key values without rewriting the KV-decrypt-entry policy
'

# Only difference between Edge and X output format
if [[ "$FORMAT" == "" || "$FORMAT" == "X" ]]; then
  FORMAT="X"
  ENTRIES_NAME=keyValueEntries
  if [[ ! -d "${OUTPUT_DIR}" ]]; then
    mkdir -p ${OUTPUT_DIR}
  fi
else
  FORMAT="Edge"
  ENTRIES_NAME=entry
  if [[ ! -d "${OUTPUT_DIR}/kvm/org" ]]; then
    mkdir -p ${OUTPUT_DIR}/kvm/org
  fi
fi

AUTH="Authorization:Basic $B64UNPW"

# Get the list of org KVMs
KVMS=$(curl -s -H "$AUTH" -s https://${HOST}/edge-facade/v1/organizations/${ORG}/keyvaluemaps | jq -r .[])
if [[ "$KVMS" == *'"error":'* ]]; then
  echo
  echo "ERROR: unauthorized."
  echo "MESSAGE: $KVMS"
  Help
  exit
fi

##################################################
# Organization

echo Organization KVMs: $ORG
for KVM in ${KVMS}
do
  # Exclude KVMS: CustomReports* privacy
  if [[ "$KVM" == *"CustomReports"* || "$KVM" == "privacy" ]]; then
    echo "Skipping $KVM"
  else
    echo "Exporting organization $KVM"
    
    # Get encryption
    ENCRYPTED=$(curl -s -H "$AUTH" -s https://$HOST/edge-facade/v1/organizations/$ORG/keyvaluemaps/$KVM | jq .encrypted)
    
    # Get the list of keys
    KEYS=$(curl -s -H "$AUTH" -s https://$HOST/edge-facade/v1/organizations/$ORG/keyvaluemaps/$KVM/keys | jq -r .[])
    
    RESPONSE='{"encrypted":'"${ENCRYPTED}"',"name":"'"${KVM}"'","'"${ENTRIES_NAME}"'":['
    FIRST=1
    for KEY in ${KEYS}
    do
      if [ "$FIRST" -eq 1 ]; then
        # invoke the Service Callout to modify the proxy KVM policy by passing callout query param set to true
        ENTRY=$(curl -s -H "$AUTH" https://$HOST/edge-facade/v1/organizations/$ORG/keyvaluemaps/$KVM/entries/$KEY?callout=true)
        RESPONSE="${RESPONSE}${ENTRY}"
        FIRST=0
      else
        # Retrieve other values from the same KVM without modifying the proxy KVM policy
        ENTRY=$(curl -s -H "$AUTH" https://$HOST/edge-facade/v1/organizations/$ORG/keyvaluemaps/$KVM/entries/$KEY?callout=false)
        RESPONSE="${RESPONSE}, ${ENTRY}"
      fi
    done
    RESPONSE="$RESPONSE"']}'

    echo $RESPONSE | jq 
    if [[ "$FORMAT" == "X" ]]; then
      echo $RESPONSE | jq > ${OUTPUT_DIR}/org__${KVM}__kvmfile__0.json
    else
      echo $RESPONSE | jq > $OUTPUT_DIR/kvm/org/$KVM
    fi
  fi
done

##################################################
# Environments

# If no ENVS passed, get all ENVS
if [[ "$ENVS" == "" ]]
then
    ENVS=$(curl -s -H "$AUTH" https://$HOST/edge-facade/v1/organizations/$ORG/environments | jq .[] -r)
fi

for E in $ENVS
do
  echo Environment KVMs: $E
  KVMS=$(curl -s -H "$AUTH" -s https://${HOST}/edge-facade/v1/organizations/${ORG}/environments/${E}/keyvaluemaps | jq -r .[])
  for KVM in ${KVMS}
  do
    echo "Exporting Environment $E $KVM"
    
    # Get encryption
    ENCRYPTED=$(curl -s -H "$AUTH" -s https://$HOST/edge-facade/v1/organizations/$ORG/environments/${E}/keyvaluemaps/$KVM | jq .encrypted)
    
    # Get the list of keys
    KEYS=$(curl -s -H "$AUTH" -s https://$HOST/edge-facade/v1/organizations/$ORG/environments/${E}/keyvaluemaps/$KVM/keys | jq -r .[])
    
    RESPONSE='{"encrypted":'"${ENCRYPTED}"',"name":"'"${KVM}"'","'"${ENTRIES_NAME}"'":['
    FIRST=1
    for KEY in ${KEYS}
    do
      if [ "$FIRST" -eq 1 ]; then
        # invoke the Service Callout to modify the proxy KVM policy by passing callout query param set to true
        ENTRY=$(curl -s -H "$AUTH" https://$HOST/edge-facade/v1/organizations/$ORG/environments/${E}/keyvaluemaps/$KVM/entries/$KEY?callout=true)
        RESPONSE="${RESPONSE}${ENTRY}"
        FIRST=0
      else
        # Retrieve other values from the same KVM without modifying the proxy KVM policy
        ENTRY=$(curl -s -H "$AUTH" https://$HOST/edge-facade/v1/organizations/$ORG/environments/${E}/keyvaluemaps/$KVM/entries/$KEY?callout=false)
        RESPONSE="${RESPONSE}, ${ENTRY}"
      fi
    done
    RESPONSE="$RESPONSE"']}'

    echo $RESPONSE | jq 
    if [[ "$FORMAT" == "X" ]]; then
      echo $RESPONSE | jq > ${OUTPUT_DIR}/env__${E}__${KVM}__kvmfile__0.json
    else
      if [[ ! -d "${OUTPUT_DIR}/kvm/env/${E}" ]]; then
        mkdir -p ${OUTPUT_DIR}/kvm/env/${E}
      fi
      echo $RESPONSE | jq > ${OUTPUT_DIR}/kvm/env/${E}/$KVM
    fi
  done
done

##################################################
# Update KVM policy to default, not-found KVM
echo Updating KVM policy to \"not-found\" KVM
curl -s -H "$AUTH" -s https://$HOST/edge-facade/v1/organizations/$ORG/keyvaluemaps/not-found/entries/entry?callout=true 2>&1 > /dev/null


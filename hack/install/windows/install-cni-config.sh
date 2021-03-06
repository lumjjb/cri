#!/bin/bash

# Copyright The containerd Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

CNI_CONFIG_DIR="${CNI_CONFIG_DIR:-"C:\\Program Files\\containerd\\cni\\conf"}"
mkdir -p "${CNI_CONFIG_DIR}"

# split_ip splits ip into a 4-element array.
split_ip() {
  local -r varname="$1"
  local -r ip="$2"
  for i in {0..3}; do
    eval "$varname"[$i]=$( echo "$ip" | cut -d '.' -f $((i + 1)) )
  done
}

# subnet gets subnet for a gateway, e.g. 192.168.100.0/24.
calculate_subnet() {
  local -r gateway="$1"
  local -r prefix_len="$2"
  split_ip gateway_array "$gateway"
  local len=$prefix_len
  for i in {0..3}; do
    if (( len >= 8 )); then
      mask=255
    elif (( len > 0 )); then
      mask=$(( 256 - 2 ** ( 8 - len ) ))
    else
      mask=0
    fi
    (( len -= 8 ))
    result_array[i]=$(( gateway_array[i] & mask ))
  done
  result="$(printf ".%s" "${result_array[@]}")"
  result="${result:1}"
  echo "$result/$((32 - prefix_len))"
}

# nat already exists on the Windows VM, the subnet and gateway
# we specify should match that.
gateway="$(powershell -c "(Get-NetIPAddress -InterfaceAlias 'vEthernet (nat)' -AddressFamily IPv4).IPAddress")"
prefix_len="$(powershell -c "(Get-NetIPAddress -InterfaceAlias 'vEthernet (nat)' -AddressFamily IPv4).PrefixLength")"

subnet="$(calculate_subnet "$gateway" "$prefix_len")"

# The "name" field in the config is used as the underlying
# network type right now (see
# https://github.com/microsoft/windows-container-networking/pull/45),
# so it must match a network type in:
# https://docs.microsoft.com/en-us/windows-server/networking/technologies/hcn/hcn-json-document-schemas
bash -c 'cat >"'"${CNI_CONFIG_DIR}"'"/0-containerd-nat.conf <<EOF
{
    "cniVersion": "0.2.0",
    "name": "nat",
    "type": "nat",
    "master": "Ethernet",
    "ipam": {
        "subnet": "'$subnet'",
        "routes": [
            {
                "gateway": "'$gateway'"
            }
        ]
    },
    "capabilities": {
        "portMappings": true,
        "dns": true
    }
}
EOF'

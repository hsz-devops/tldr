#!/bin/bash

# Copyright 2016 The Lightweight Docker Runtime contributors
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

# Sets up the node that contains all infrastructure components (logging, monitoring, Consul, etc)

TLDR_ROOT=$(dirname ${BASH_SOURCE[0]})/..
TLDR_BIN=$TLDR_ROOT/bin
source $TLDR_BIN/utils.sh

# Creates infra node if needed
detect_provider
info "Using provider: ${TLDR_PROVIDER}"
source $TLDR_BIN/providers/$TLDR_PROVIDER/provider.sh

# delegate node provisioning and preparation to the provider
create_infra_node

# retrieve the IP address of the registry node so that we can deploy infrastructure containers
REGISTRY=$(docker-machine ip $REGISTRY_MACHINE_NAME):5000

# Start Consul if not already running
if ! docker inspect consul &> /dev/null; then
  info "Starting Consul"
  docker run -d -p 53:53 -p 53:53/udp -p 8500:8500 --name consul $REGISTRY/consul -server -bootstrap-expect 1
else
  info "Consul already running"
fi

# Start registrator for this node if not already running
if ! docker inspect registrator &> /dev/null; then
  info "Starting Registrator"
  docker run -d --dns 172.17.0.1 \
           -v /var/run/docker.sock:/tmp/docker.sock \
           -h registrator \
           --name registrator \
           $REGISTRY/registrator \
           -internal consul://consul.service.consul:8500
else
  info "Registrator already running"
fi

# set up the logging components
eval $(docker-machine env $INFRA_MACHINE_NAME)
REGISTRY=$REGISTRY docker-compose -f components/elk/docker-compose.yml up -d

# and the monitoring components
REGISTRY=$REGISTRY docker-compose -f components/monitoring/docker-compose.yml up -d
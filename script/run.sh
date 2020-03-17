#!/bin/bash

[ -z "${FQDN}" ] && { echo "FQDN env var is empty"; exit 1; }

docker run -it --rm -v $(pwd):/home \
    -e DEFAULT_COUNTRY \
    -e DEFAULT_PROVINCE \
    -e DEFAULT_ORG \
    -e FQDN \
    lowply/rootca

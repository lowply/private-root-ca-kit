#!/bin/bash

[ -z "${FQDN}" ] && { echo "FQDN env var is empty"; exit 1; }
docker run -it --rm -v $(pwd):/home -e FQDN lowply/rootca

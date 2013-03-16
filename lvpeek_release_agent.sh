#!/bin/sh
exec < /dev/null
exec >> /tmp/lvpeek_release_agent.log
exec 2>&1
$(dirname $0)/lvpeek.rb --release "$1"

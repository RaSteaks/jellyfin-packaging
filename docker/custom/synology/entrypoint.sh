#!/bin/bash
set -eu

# A failed first build must not open the existing database with another server.
# Later failures can use the last fully built set for this architecture.
arch=$(dpkg --print-architecture)
update_status=0
/opt/jellyfin-updater/update-components.sh "$arch" || update_status=$?
if ((update_status != 0)); then
    if [[ $(cat /components/current/architecture 2>/dev/null || :) != "$arch" ]]; then
        # Status 65 means a component build or its output check failed. Hold
        # this boot so unless-stopped cannot repeat a long failed compilation.
        if ((update_status == 65)); then
            echo "Initial component build failed. Check the build log, correct the cause, then restart the jellyfin service to retry." >&2
            trap 'exit 0' TERM INT
            sleep infinity &
            wait "$!"
        fi
        echo "No complete $arch component set is available. Jellyfin was not started." >&2
        exit "$update_status"
    fi
    echo "Update failed; starting the previously selected component set." >&2
fi
exec /components/current/server/jellyfin "$@"

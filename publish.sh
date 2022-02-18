#! /bin/bash

exit_on_error() {
    exit_code=$1
    last_command=${@:2}
    echo "exit code: $1"
    if [[ $exit_code -ne 0 ]]; then
        >&2 echo "\"${last_command}\" command failed with exit code ${exit_code}."
        exit $exit_code
    fi
    echo "successful"
}

PACKAGE_PATH="$1"
shift
INSTALL_HUB_ID=0
PROD_CHANNEL_ID="2076fb52-0ef5-4db9-aa7d-34fb6de0b6a8"
BETA_CHANNEL_ID="b9930d5a-f3f5-4428-b378-b12cb3d93093"
CHANNEL_ID=$PROD_CHANNEL_ID
parse_args() {
    while [ $# -gt 0 ]; do
        local key="$1"
        echo "$key"
        case "$key" in
            --install)
                INSTALL_HUB_ID="$2"
                shift
                ;;
            --beta)
                CHANNEL_ID=$BETA_CHANNEL_ID
                ;;
            *)
                ;;
        esac
        shift
    done
}
parse_args $@
echo "packaging $PACKAGE_PATH"

ID="$(st edge:drivers:package $PACKAGE_PATH --json | jq -r ".driverId")"
exit_on_error $?
echo "publishing $ID to $CHANNEL_ID"
st edge:drivers:publish $ID -C $CHANNEL_ID
exit_on_error $?

if [ ! -z "$INSTALL_HUB_ID" ]; then
    echo "Installing $ID $INSTALL_HUB_ID $CHANNEL_ID"
    st edge:drivers:install "$ID" -H="$INSTALL_HUB_ID" -C="$CHANNEL_ID"
    exit_on_error $?
fi


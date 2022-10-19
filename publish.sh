#! /bin/bash

exit_on_error() {

    if [[ $exit_code -ne 0 ]]; then
        >&2  echo "command failed with exit code $1."
        exit $exit_code
    fi
    echo "successful"
}

PACKAGE_PATH="$1"
shift
INSTALL_HUB_ID=0
PROD_CHANNEL_ID="2076fb52-0ef5-4db9-aa7d-34fb6de0b6a8"
BETA_CHANNEL_ID="b9930d5a-f3f5-4428-b378-b12cb3d93093"

if test -f "ids_env"; then
    source "ids_env"
fi


CHANNEL_ID=$PROD_CHANNEL_ID
parse_args() {
    while [ $# -gt 0 ]; do
        local key="$1"
        echo "$key"
        case "$key" in
            --install)
                case $2 in
                    personal)
                        INSTALL_HUB_ID=$PERSONAL_HUB_ID
                        ;;
                    v3)
                        INSTALL_HUB_ID=$PROD_V3_HUB_ID
                        ;;
                    v2)
                        INSTALL_HUB_ID=$PROD_V2_HUB_ID
                        ;;
                    *)
                        INSTALL_HUB_ID="$2"
                    ;;
                esac
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
PACKAGE_JSON="$(st edge:drivers:package $PACKAGE_PATH --json)"
echo $?
exit_on_error $?
ID="$(echo "$PACKAGE_JSON" | jq -r ".driverId")"
echo "publishing $ID to $CHANNEL_ID"
st edge:drivers:publish $ID -C $CHANNEL_ID
exit_on_error $? "$(echo "!:0")" "!:*"

if [ ! -z "$INSTALL_HUB_ID" ]; then
    echo "Installing $ID $INSTALL_HUB_ID $CHANNEL_ID"
    st edge:drivers:install "$ID" -H="$INSTALL_HUB_ID" -C="$CHANNEL_ID"
    exit_on_error $? "!:0" "!:*"
fi

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

echo "packaging $1"
CHANNEL_ID="2076fb52-0ef5-4db9-aa7d-34fb6de0b6a8"
ID="$(st edge:drivers:package $1 --json | jq -r ".driverId")"
exit_on_error $?
echo "publishing $ID to $CHANNEL_ID"
st edge:drivers:publish $ID -C $CHANNEL_ID
exit_on_error $?

if [ ! -z "$2" ] && [ "$2" == "--install" ] && [ ! -z "$3" ]; then
    echo "Installing $ID $3 $CHANNEL_ID"
    st edge:drivers:install "$ID" -H="$3" -C="$CHANNEL_ID"
    exit_on_error $?
fi


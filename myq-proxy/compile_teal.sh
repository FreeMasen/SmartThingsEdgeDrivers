#! /bin/bash

for file in ./teal/*
do
    FILENAME="$(basename "$file")"
    NEW_FILENAME=$(echo "$FILENAME" | sed "s/tl$/lua/")
    tl gen -o "./src/$NEW_FILENAME" "$file"
done

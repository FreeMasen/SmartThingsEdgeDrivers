#! /bin/bash

CSS=""
JS=""
HTML=""
OUT_FILE="$2"

for entry in "$1"/*
do
  if [[ $entry == *.css ]]
  then
    CSS="$(cat "$entry")"
  fi
  if [[ $entry == *.js ]]
  then
    JS="$(cat "$entry")"
  fi
  if [[ $entry == *.html ]]
  then
    HTML="$(cat "$entry")"
  fi
done
echo "" > $OUT_FILE

append_line() {
    echo "$1" >> $OUT_FILE
}

append_line ""
append_line "local function css()"
append_line "  return [["
echo "$CSS" >> $OUT_FILE
append_line "  ]]"
append_line "end"
append_line ""
append_line "local function js()"
append_line "  return [["
echo "$JS" >> $OUT_FILE
append_line "  ]]"
append_line "end"
append_line ""
append_line "local function html()"
append_line "  return [["
echo "$HTML" >> $OUT_FILE
append_line "  ]]"
append_line "end"
append_line ""
append_line "return {"
append_line "  css = css,"
append_line "  js = js,"
append_line "  html = html,"
append_line "}"

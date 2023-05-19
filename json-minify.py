#!/usr/bin/env python3
# usage: python3 json-minify.py <path-to-source-json-file>

import sys
import json

source_json_path = sys.argv[1]
with open(source_json_path) as json_file:
    json_data_str = json_file.read()
json_obj = json.loads(json_data_str)
json_data_str_unindented = json.dumps(json_obj)
print(json_data_str_unindented, end='')

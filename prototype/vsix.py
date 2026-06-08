#!/usr/bin/env python3   

import sys

unique_identifier = sys.argv[1]
version = sys.argv[2] if len(sys.argv) > 2 else 'latest'
target_platform = sys.argv[3] if len(sys.argv) > 3 else ""

publisher, package = unique_identifier.split('.')
url = (
    f'https://marketplace.visualstudio.com/_apis/public/gallery/publishers/{publisher}/vsextensions/{package}/{version}/vspackage'
    + (f'?targetPlatform={target_platform}' if target_platform != '' else ''))
print(url)

import os
import json

path = "/Users/liu/Desktop/Toolbox.app/Contents/Resources/Scripts"
files = os.listdir(path)
print("Files in bundle (hex):")
for f in files:
    if f.endswith('.command'):
        print(f"  {f}: {f.encode('utf-8').hex()}")

config_path = "/Users/liu/Desktop/Toolbox.app/Contents/Resources/tool_config.json"
with open(config_path, 'r') as f:
    config = json.load(f)

print("\nScripts in tool_config.json (hex):")
for tool in config:
    p = tool['scriptRelativePath']
    print(f"  {p}: {p.encode('utf-8').hex()}")

import os
import json

path = "/Users/liu/Desktop/Toolbox.app/Contents/Resources/Scripts"
files = os.listdir(path)
print("Files in bundle (repr):")
for f in files:
    print(f"  {repr(f)}")

config_path = "/Users/liu/Desktop/Toolbox.app/Contents/Resources/tool_config.json"
with open(config_path, 'r') as f:
    config = json.load(f)

print("\nScripts in tool_config.json (repr):")
for tool in config:
    print(f"  {repr(tool['scriptRelativePath'])}")

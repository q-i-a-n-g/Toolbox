#!/bin/bash
xcodebuild -scheme Toolbox build 2>&1 | tee build.log

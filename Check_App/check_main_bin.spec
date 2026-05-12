# -*- mode: python ; coding: utf-8 -*-
# 使用 onedir + Playwright 数据文件：onefile 大包在本机测试中出现长时间无响应，目录分发更稳定。

from PyInstaller.utils.hooks import collect_data_files

playwright_datas = collect_data_files("playwright")

a = Analysis(
    ["check_main.py"],
    pathex=[],
    binaries=[],
    datas=playwright_datas,
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="check_main_bin",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="check_main_bin",
)

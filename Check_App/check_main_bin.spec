# -*- mode: python ; coding: utf-8 -*-
# 使用 onedir + Playwright 数据文件：onefile 大包在本机测试中出现长时间无响应，目录分发更稳定。

from PyInstaller.utils.hooks import collect_data_files

playwright_datas = collect_data_files("playwright")

a_check = Analysis(
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
pyz_check = PYZ(a_check.pure)

exe_check = EXE(
    pyz_check,
    a_check.scripts,
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

a_daily = Analysis(
    ["daily_assign_main.py"],
    pathex=[],
    binaries=[],
    datas=playwright_datas,
    hiddenimports=['playwright'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz_daily = PYZ(a_daily.pure)

exe_daily = EXE(
    pyz_daily,
    a_daily.scripts,
    [],
    exclude_binaries=True,
    name="daily_assign_main_bin",
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
    exe_check,
    a_check.binaries,
    a_check.zipfiles,
    a_check.datas,
    exe_daily,
    a_daily.binaries,
    a_daily.zipfiles,
    a_daily.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="check_main_bin",
)

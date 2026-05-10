import openpyxl
import os

data_dir = 'data'
files = ['AI.xlsx', '分数.xlsx', '答题卡-AI.xlsx', '答题卡-分数.xlsx']

for f in files:
    fpath = os.path.join(data_dir, f)
    if os.path.exists(fpath):
        try:
            wb = openpyxl.load_workbook(fpath, data_only=True, read_only=True)
            h = [str(c) for c in next(wb.active.iter_rows(min_row=1, max_row=1, values_only=True), []) if c]
            print(f"File: {f}, Headers: {h}")
        except Exception as e:
            print(f"File: {f}, Error: {e}")
    else:
        print(f"File: {f} not found")

# 每周检查工具 (Start.app) 使用说明

自动下载、生成周期任务检查的表格

##  核心功能

- 自动打开统计详情页，下载 `AI、答题卡` 的表格
- 下载后的文件会自动重命名并存放到 `data` 文件夹
- 自动处理下载的表格，生成 `result.xlsx` 供检查。


## 使用

1.  把每日任务的`分配表` (`周期`或`周期+答题卡`)复制保存到 `data` 文件夹。
    - 例子： `https://docs.qq.com/sheet/DV2VkSXdBTEFvSG5p?tab=toe7ro`
2.  双击 `Start.app` 图标
    - ![示例](screenShot/1.png)
    - ![示例](screenShot/2.png)
3.  运行结束，生成`result.xlsx` 文件。
    - ![示例](screenShot/3.png)
4.  小功能：`拼链接`
    - 断开网络，把 周期+答题卡 的`分配表`放在`data`文件夹，运行app，得到拼好的链接
    - ![示例](screenShot/4.png)
    - ![示例](screenShot/5.png)
5.  小功能：`重命名文件`
    - 断开网络，把 周期+答题卡 的`统计详情表`放在`data`文件夹，运行app，自动根据表格的内容重命名
    - ![示例](screenShot/6.png)
    - ![示例](screenShot/7.png)

## tips
- 首次运行，自动下载表格时，`需要登录`，之后就不用了
- 无需手动删除旧文件，可`自动覆盖`
- 首次双击打不开app的，需要`右键打开`，自动授权，之后就可直接双击打开了
-  周期+答题卡 的`分配表`，可以是：1个excel表 + 2个sheet，也可以是2个excel表
    - ![示例](screenShot/8.png)
    - ![示例](screenShot/9.png)

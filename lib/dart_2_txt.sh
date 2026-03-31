#!/bin/bash

# 脚本名称：convert_dart_to_txt.sh
# 功能：将当前目录下所有 .dart 文件复制为 .txt 后缀

# 检查当前目录下是否存在 .dart 文件
# shopt -s nullglob 确保如果没有匹配文件，循环不会执行且不会报错
shopt -s nullglob
dart_files=(*.dart)

if [ ${#dart_files[@]} -eq 0 ]; then
    echo "当前目录下没有找到 .dart 文件。"
    exit 0
fi

echo "正在处理 ${#dart_files[@]} 个文件..."

# 遍历所有 .dart 文件
for file in "${dart_files[@]}"; do
    # 获取文件名（不含路径）
    filename=$(basename "$file")
    
    # 构建新的文件名：将 .dart 替换为 .txt
    # ${filename%.*} 去除后缀，然后加上 .txt
    new_filename="${filename%.*}.txt"
    
    # 执行复制操作
    # -i 参数会在目标文件存在时询问是否覆盖（防止误操作）
    # 如果不需要询问，可以去掉 -i
    cp -i "$file" "$new_filename"
    
    if [ $? -eq 0 ]; then
        echo "成功: $filename -> $new_filename"
    else
        echo "跳过或失败: $filename"
    fi
done

echo "处理完成。"

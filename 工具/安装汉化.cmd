@echo off
rem 安装 STM32CubeIDE 汉化（写入安装目录，需已获授权）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0安装汉化.ps1" %*
pause

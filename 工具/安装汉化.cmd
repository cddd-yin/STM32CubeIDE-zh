@echo off
chcp 936 >nul
title STM32CubeIDE 汉化安装
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0安装汉化.ps1"
pause

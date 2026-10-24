@echo off
chcp 936 >nul
title STM32CubeIDE 还原英文
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0还原英文.ps1"
pause

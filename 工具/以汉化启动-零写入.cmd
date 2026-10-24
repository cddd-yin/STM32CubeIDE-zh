@echo off
chcp 936 >nul
title STM32CubeIDE 零写入汉化启动
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0以零写入启动.ps1"

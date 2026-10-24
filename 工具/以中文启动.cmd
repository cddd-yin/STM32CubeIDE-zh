@echo off
chcp 936 >nul
title STM32CubeIDE 以中文启动
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0以中文启动.ps1"

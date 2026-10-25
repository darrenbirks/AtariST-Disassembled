@echo off
rem Build all three releases with build.cmd, each in build\<release>\.
setlocal
cd /d "%~dp0"
set FAILED=
for %%C in (RETAIL_2DISK RETAIL_1DISK BUDGET_1DISK) do (
  call "%~dp0build.cmd" %%C
  if errorlevel 1 set FAILED=1
)
if defined FAILED (
  echo Not every release built.
  exit /b 1
)
echo All three releases built.

@rem Gradle launcher (Windows). See gradlew for the reasoning.
@echo off
setlocal enabledelayedexpansion

set APP_HOME=%~dp0
set PROPS=%APP_HOME%gradle\wrapper\gradle-wrapper.properties

for /f "tokens=2 delims==" %%A in ('findstr /b "distributionUrl=" "%PROPS%"') do set DIST_URL=%%A
set DIST_URL=%DIST_URL:\:=:%
set DIST_URL=%DIST_URL:\=%
for %%A in ("%DIST_URL%") do set DIST_NAME=%%~nA

set CACHE_ROOT=%USERPROFILE%\.gradle\wrapper\dists
if not "%GRADLE_USER_HOME%"=="" set CACHE_ROOT=%GRADLE_USER_HOME%\wrapper\dists
set DIST_DIR=%CACHE_ROOT%\%DIST_NAME%

set GRADLE_BIN=
if exist "%DIST_DIR%\%DIST_NAME%\bin\gradle.bat" set GRADLE_BIN=%DIST_DIR%\%DIST_NAME%\bin\gradle.bat

if "%GRADLE_BIN%"=="" (
  echo Downloading %DIST_URL%
  powershell -NoProfile -Command "$d='%DIST_DIR%'; if(-not (Test-Path $d)){New-Item -ItemType Directory -Path $d | Out-Null}; Invoke-WebRequest -Uri '%DIST_URL%' -OutFile \"$d\dist.zip\"; Expand-Archive -Force \"$d\dist.zip\" $d; Remove-Item \"$d\dist.zip\"; Get-ChildItem -Path $d -Recurse -Filter gradle.bat | Select-Object -First 1 | ForEach-Object { $_.FullName } | Set-Content \"$d\bin-path.txt\""
  if exist "%DIST_DIR%\bin-path.txt" set /p GRADLE_BIN=<"%DIST_DIR%\bin-path.txt"
)

if "%GRADLE_BIN%"=="" (
  echo Could not locate a Gradle distribution. Run the build on macOS/Linux or install Gradle.
  exit /b 1
)

call "%GRADLE_BIN%" -p "%APP_HOME%" %*

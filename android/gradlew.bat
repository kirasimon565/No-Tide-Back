@rem Gradle launcher (Windows). Downloads the distribution pinned in
@rem gradle/wrapper/gradle-wrapper.properties, then delegates to it.
@echo off
setlocal
set APP_HOME=%~dp0
set PROPS=%APP_HOME%gradle\wrapper\gradle-wrapper.properties
for /f "tokens=2 delims==" %%a in ('findstr /b "distributionUrl=" "%PROPS%"') do set DIST_URL=%%a
set DIST_URL=%DIST_URL:\:=:%
for %%f in ("%DIST_URL%") do set DIST_NAME=%%~nf
set GRADLE_DIR=%USERPROFILE%\.gradle\wrapper\dists\%DIST_NAME%
if not exist "%GRADLE_DIR%\%DIST_NAME%\bin\gradle.bat" (
  echo Downloading %DIST_URL%
  powershell -NoProfile -Command "Invoke-WebRequest -Uri '%DIST_URL%' -OutFile '%GRADLE_DIR%\dist.zip'"
  powershell -NoProfile -Command "Expand-Archive -Force '%GRADLE_DIR%\dist.zip' '%GRADLE_DIR%'"
  del "%GRADLE_DIR%\dist.zip"
)
call "%GRADLE_DIR%\%DIST_NAME%\bin\gradle.bat" -p "%APP_HOME%" %*
endlocal

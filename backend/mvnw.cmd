@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "WRAPPER_JAR=%SCRIPT_DIR%\.mvn\wrapper\maven-wrapper.jar"

where java >nul 2>nul
if errorlevel 1 (
    echo Java is required to run the Maven Wrapper. 1>&2
    exit /b 1
)

if not exist "%WRAPPER_JAR%" (
    echo Maven Wrapper JAR is missing from backend\.mvn\wrapper. 1>&2
    exit /b 1
)

java -classpath "%WRAPPER_JAR%" "-Dmaven.multiModuleProjectDirectory=%SCRIPT_DIR%" org.apache.maven.wrapper.MavenWrapperMain %*
exit /b %ERRORLEVEL%

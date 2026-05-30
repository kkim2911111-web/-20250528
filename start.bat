@echo off
chcp 65001 >nul
cd /d C:\Users\kkim2\danjicar_app

rem 3초 후 브라우저 열기 (Flutter web 서버 기동과 병렬)
start "" cmd /c "timeout /t 3 /nobreak >nul && start http://localhost:3000"

flutter run -d chrome --web-port=3000

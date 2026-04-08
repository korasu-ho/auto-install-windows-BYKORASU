@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

echo ======================================
echo  Auto Push Project to GitHub

echo  Repo: https://github.com/korasu-ho/auto-install-windows-BYKORASU.git
echo ======================================
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Git belum terpasang atau belum masuk PATH.
  echo Install dulu: https://git-scm.com/download/win
  pause
  exit /b 1
)

set "REPO_URL=https://github.com/korasu-ho/auto-install-windows-BYKORASU.git"

for /f "delims=" %%i in ('git config --global user.name 2^>nul') do set "GIT_USER=%%i"
for /f "delims=" %%i in ('git config --global user.email 2^>nul') do set "GIT_EMAIL=%%i"

if not defined GIT_USER (
  set /p GIT_USER=Masukkan GitHub name, contoh korasu-ho: 
  if not defined GIT_USER (
    echo [ERROR] Nama tidak boleh kosong.
    pause
    exit /b 1
  )
  git config --global user.name "!GIT_USER!"
)

if not defined GIT_EMAIL (
  set /p GIT_EMAIL=Masukkan GitHub email: 
  if not defined GIT_EMAIL (
    echo [ERROR] Email tidak boleh kosong.
    pause
    exit /b 1
  )
  git config --global user.email "!GIT_EMAIL!"
)

if not exist ".git" (
  echo [INFO] Inisialisasi repository git...
  git init
  if errorlevel 1 goto :fail
)

if not exist ".gitattributes" (
  > .gitattributes echo *.sh text eol=lf
)

echo [INFO] Menambahkan file ke staging...
git add .
if errorlevel 1 goto :fail

echo [INFO] Commit perubahan...
git commit -m "update auto installer" >nul 2>nul
if errorlevel 1 (
  echo [INFO] Tidak ada perubahan baru untuk di-commit.
)

git branch -M main
if errorlevel 1 goto :fail

git remote get-url origin >nul 2>nul
if errorlevel 1 (
  echo [INFO] Menambahkan remote origin...
  git remote add origin "%REPO_URL%"
  if errorlevel 1 goto :fail
) else (
  echo [INFO] Update remote origin...
  git remote set-url origin "%REPO_URL%"
  if errorlevel 1 goto :fail
)

echo [INFO] Push ke GitHub...
git push -u origin main
if errorlevel 1 goto :fail

echo.
echo [SUKSES] Push selesai.
echo Kalau diminta login, pakai GitHub username + Personal Access Token.
pause
exit /b 0

:fail
echo.
echo [ERROR] Proses gagal. Cek pesan error di atas.
pause
exit /b 1

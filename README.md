# Auto Install Windows on DigitalOcean Droplet (QEMU)

Script ini meng-install Windows **di dalam VM QEMU** pada droplet Linux Anda.

Penting:
- DigitalOcean droplet standar tidak menyediakan image Windows native untuk host OS droplet.
- Jadi pendekatan ini adalah nested VM (Windows berjalan di atas Linux droplet).
- Performa bergantung apakah akselerasi KVM tersedia. Script sudah fallback ke TCG bila KVM tidak tersedia.
- Pastikan lisensi Windows Anda valid.

## Spesifikasi yang dipakai
Default script sudah diset untuk droplet 4 vCPU / 8 GB RAM:
- vCPU VM: 4
- RAM VM: 6144 MB
- Disk: 64 GB

Anda bisa override dengan environment variable.

## File
- install_windows_auto.sh: siapkan dependency + unattended install
- start_windows_vm.sh: boot normal setelah install selesai
- stop_windows_vm.sh: hentikan VM
- diagnose_rdp.sh: diagnosa cepat masalah koneksi RDP
- droplet_one_shot_setup.sh: one-shot setup dari droplet baru

## Cara pakai
### 0) Prasyarat (wajib)
Di DigitalOcean firewall/security group, buka inbound:
- TCP 3389 (RDP)
- TCP 5901 (VNC monitor installer)

### 1) Jika Anda sudah di terminal droplet (alur paling jelas)
Jalankan perintah ini satu per satu:

```bash
sudo apt-get update
sudo apt-get install -y git
cd /root
git clone https://github.com/korasu-ho/auto-install-windows-BYKORASU.git
cd auto-install-windows-BYKORASU
chmod +x install_windows_auto.sh start_windows_vm.sh stop_windows_vm.sh diagnose_rdp.sh droplet_one_shot_setup.sh
```

Lalu mulai installer (contoh Windows Server 2022):

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=3 ./install_windows_auto.sh
```

Pilihan `WIN_VERSION_CHOICE`:
- `1` = Windows Server 2016
- `2` = Windows Server 2019
- `3` = Windows Server 2022
- `4` = custom URL (wajib isi `ISO_URL`)

Catatan pilihan `1-3`:
- Source ISO adalah Microsoft Evaluation media.
- Script unattended sudah diset untuk suppress tampilan input product key saat setup.

Contoh custom URL ISO:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=4 ISO_URL='https://contoh-domain.com/windows-server.iso' ./install_windows_auto.sh
```

Catatan:
- `ISO_URL` harus direct link file `.iso` (bisa di-download langsung oleh `wget/curl`).
- Link share `mega.nz/file/...` sekarang didukung otomatis oleh script (akan pakai `megatools`).
- Link Google Drive (`drive.google.com/...`) sekarang didukung otomatis oleh script (akan pakai `gdown`).

Contoh custom URL Mega (langsung):

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=4 ISO_URL='https://mega.nz/file/ELBxwISD#ZhALWVoo4sLdUwcfLSZbSka3HoRYE2m5it7WAWCJREE' ./install_windows_auto.sh
```

Contoh custom URL Google Drive:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=4 ISO_URL='https://drive.google.com/file/d/FILE_ID/view?usp=sharing' ./install_windows_auto.sh
```

### 2) Pantau proses install
- Buka VNC ke `IP_DROPLET:5901`
- Tunggu setup Windows selesai dan reboot

### 3) Setelah install selesai
Pindah dari mode installer ke mode normal boot:

```bash
sudo ./stop_windows_vm.sh
sudo ./start_windows_vm.sh
```

Login dari Windows lokal via RDP ke `IP_DROPLET:3389`.

### 4) Opsi super cepat (one-shot)
Jika ingin satu perintah dari droplet baru:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=3 bash -c "$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_one_shot_setup.sh)"
```

Untuk `WIN_VERSION_CHOICE=4` (custom URL), gunakan:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=4 ISO_URL='https://contoh-domain.com/windows-server.iso' bash -c "$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_one_shot_setup.sh)"
```

Contoh one-shot dengan link Mega:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=4 ISO_URL='https://mega.nz/file/ELBxwISD#ZhALWVoo4sLdUwcfLSZbSka3HoRYE2m5it7WAWCJREE' bash -c "$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_one_shot_setup.sh)"
```

Contoh one-shot dengan Google Drive:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=4 ISO_URL='https://drive.google.com/file/d/FILE_ID/view?usp=sharing' bash -c "$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_one_shot_setup.sh)"
```

Verifikasi ISO yang dipakai saat custom URL:
- Untuk `WIN_VERSION_CHOICE=4`, script akan pakai `windows_custom.iso`.
- Script menyimpan sumber URL di `/opt/winvm/.iso_source_url`.
- Jika URL berubah, ISO lama otomatis diganti.

Cek cepat di droplet:

```bash
ls -lh /opt/winvm/windows_custom.iso
cat /opt/winvm/.iso_source_url
```

Kalau mau super yakin 100% fresh sebelum run ulang:

```bash
sudo rm -f /opt/winvm/windows_custom.iso /opt/winvm/.iso_source_url
```

### 5) Catatan RDP otomatis
Script sudah otomatis saat first logon:
- enable RDP,
- buka firewall remote desktop,
- allow TCP 3389 eksplisit,
- set `TermService` auto-start dan start service,
- disable NLA untuk kompatibilitas client.

## Variable penting
- VM_CPUS (default: 4)
- VM_RAM_MB (default: 6144)
- DISK_GB (default: 64)
- ISO_URL (opsional jika ISO belum ada)
- WIN_VERSION_CHOICE (opsional: 1/2/3/4)
- ISO_PATH (default: /opt/winvm/windows.iso)
- RDP_HOST_PORT (default: 3389)
- VNC_DISPLAY (default: 1 -> port 5901)

Contoh override:

```bash
sudo VM_CPUS=3 VM_RAM_MB=6144 DISK_GB=80 WIN_ADMIN_PASSWORD='PasswordKuatAnda!' ./install_windows_auto.sh
```

## Catatan firewall
Buka port berikut di firewall droplet/security group:
- TCP 3389 (RDP)
- TCP 5901 (VNC, opsional untuk monitor installer)

## Troubleshooting cepat
- Cek proses QEMU:

```bash
ps aux | grep qemu-system-x86_64
```

- Jalankan diagnosa RDP end-to-end dari host droplet:

```bash
chmod +x diagnose_rdp.sh
sudo ./diagnose_rdp.sh
```

- Jika muncul error `Windows cannot locate the disk and partition specified`:

```bash
sudo ./stop_windows_vm.sh
sudo rm -f /opt/winvm/winvm.qcow2 /opt/winvm/Autounattend.xml /opt/winvm/autounattend.iso
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' VM_MACHINE='pc' WIN_VERSION_CHOICE=3 ./install_windows_auto.sh
```

Catatan:
- Ini bukan masalah driver ethernet.
- Untuk setup ini, Windows tidak perlu driver storage tambahan karena disk dipasang sebagai IDE/SATA kompatibel.
- Script sekarang default ke machine `pc` dan target instalasi menggunakan partisi available (lebih kompatibel dibanding hardcode partition ID).

- Jika VM berat/lambat, turunkan VM_CPUS dan/atau VM_RAM_MB.
- Jika install gagal, cek ISO Anda (wajib ISO bootable x64).

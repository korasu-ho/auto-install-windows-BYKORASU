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
- install_windows_native_disk.sh: deploy image Windows langsung ke disk droplet (tanpa QEMU)
- droplet_native_one_shot_setup.sh: one-shot setup mode native hard drive
- export_qcow2_to_gz.sh: export hasil install QEMU (opsi 1-3) ke image `.img.gz`
- start_windows_vm.sh: boot normal setelah install selesai
- stop_windows_vm.sh: hentikan VM
- diagnose_rdp.sh: diagnosa cepat masalah koneksi RDP
- droplet_one_shot_setup.sh: one-shot setup dari droplet baru

## Mode yang tersedia
1. Mode ringan (direct/native hard drive, tanpa QEMU runtime)
2. Mode nested VM (Ubuntu host + Windows guest via QEMU)

Jika target Anda performa maksimum pada RAM 8 GB, gunakan mode direct/native hard drive.

## Mode ringan: direct/native hard drive (rekomendasi untuk performa)
Mode ini menulis image Windows langsung ke disk droplet (`/dev/vda`), jadi tidak ada pembagian RAM Ubuntu+VM saat runtime.

Penting sebelum mulai:
- Jalankan dari environment Recovery ISO DigitalOcean.
- Siapkan URL image Windows yang sudah siap boot + RDP (format `.img`, `.img.gz`, `.img.xz`, atau sejenisnya).
- Ini akan menghapus isi disk target.

Langkah:

```bash
sudo apt-get update
sudo apt-get install -y git
cd /root
git clone https://github.com/korasu-ho/auto-install-windows-BYKORASU.git
cd auto-install-windows-BYKORASU
chmod +x install_windows_native_disk.sh
```

Contoh deploy image `.img.gz`:

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://contoh-domain.com/windows-server.img.gz' SOURCE_TYPE=gz ./install_windows_native_disk.sh
```

Contoh deploy dari Google Drive:

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://drive.google.com/file/d/FILE_ID/view?usp=sharing' SOURCE_TYPE=raw ./install_windows_native_disk.sh
```

Contoh deploy dari Mega:

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://mega.nz/file/XXXX#KEY' SOURCE_TYPE=raw ./install_windows_native_disk.sh
```

One-shot mode native (jalan dari Recovery ISO):

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://contoh-domain.com/windows-server.img.gz' SOURCE_TYPE=gz bash -c "$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_native_one_shot_setup.sh)"
```

Setelah deploy selesai:
1. Di panel DigitalOcean, ubah boot ke `Boot from Hard Drive`.
2. Power cycle droplet.
3. Buka TCP 3389 di firewall DigitalOcean.
4. Connect RDP dari lokal ke `IP_DROPLET:3389`.

Catatan penting RDP mode native:
- Script deploy memastikan image ditulis ke disk dengan benar.
- Koneksi RDP bergantung pada image Windows yang Anda pakai (harus sudah mengaktifkan RDP + network driver).

### Migrasi dari opsi 1-3 (QEMU) ke mode native hard drive
Jika Anda sudah install Windows via opsi `1-3` dan RDP sudah normal di mode QEMU, lakukan ini untuk pindah ke mode native yang lebih ringan:

1. Export disk QEMU ke image:

```bash
cd /root/auto-install-windows-BYKORASU
chmod +x export_qcow2_to_gz.sh
sudo ./export_qcow2_to_gz.sh
```

Output default: `/opt/winvm/export/windows-from-qcow2.img.gz`

2. Upload file `.img.gz` ke URL eksternal (DO Spaces / S3 / server download Anda).

3. Boot droplet ke `Recovery ISO`, lalu deploy image ke disk utama:

```bash
cd /root/auto-install-windows-BYKORASU
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://url-anda/windows-from-qcow2.img.gz' SOURCE_TYPE=gz ./install_windows_native_disk.sh
```

Alternatif jika file image sudah ada lokal di recovery environment:

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_FILE='/path/windows-from-qcow2.img.gz' SOURCE_TYPE=gz ./install_windows_native_disk.sh
```

4. Setelah selesai:
1. Ubah boot ke `Boot from Hard Drive`.
2. Reboot/power cycle.
3. Pastikan firewall DO membuka TCP `3389`.
4. RDP dari lokal ke `IP_DROPLET:3389`.

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

Urutan setelah install di VNC agar bisa RDP dari lokal:
1. Tunggu Windows selesai setup hingga masuk desktop/login.
2. Kembali ke terminal droplet, jalankan:

```bash
sudo ./stop_windows_vm.sh
sudo ./start_windows_vm.sh
```

3. Pastikan firewall DigitalOcean membuka TCP `3389`.
4. Dari PC lokal, buka `mstsc` lalu konek ke `IP_DROPLET:3389`.
5. Login dengan user `Administrator` dan password dari `WIN_ADMIN_PASSWORD`.

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

- Jika install/start gagal karena proses QEMU lama masih nyangkut, jalankan reset cepat:

```bash
sudo ./stop_windows_vm.sh
sudo pkill -f qemu-system-x86_64 || true
sudo rm -f /opt/winvm/qemu-install.pid /opt/winvm/qemu-run.pid
```

- Jika gagal karena port RDP bentrok (`Could not set up host forwarding rule tcp::3389-:3389`):

```bash
sudo ss -ltnp | grep :3389
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' RDP_HOST_PORT=3390 WIN_VERSION_CHOICE=3 ./install_windows_auto.sh
```

Lalu konek RDP ke `IP_DROPLET:3390` dan buka TCP `3390` di firewall DigitalOcean.

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

# Auto Install Windows on DigitalOcean Droplet

Project ini menyediakan 2 mode instalasi Windows di DigitalOcean:

1. Mode Native Hard Drive (lebih ringan, performa lebih tinggi)
2. Mode Nested VM QEMU (lebih aman untuk eksperimen, Ubuntu tetap jadi host)

---

## Ringkasan Mode

### 1) Native Hard Drive (Recommended untuk performa)
- Menulis image Windows langsung ke disk droplet (`/dev/vda`).
- Tidak ada overhead QEMU saat runtime.
- Cocok jika target Anda RDP performa tinggi di RAM 8 GB.

### 2) Nested VM QEMU
- Ubuntu tetap berjalan sebagai host.
- Windows jalan sebagai guest VM (QEMU).
- Lebih mudah recovery karena SSH Ubuntu tetap tersedia.

---

## File Script

- `install_windows_native_disk.sh`: deploy image Windows langsung ke disk droplet (native)
- `droplet_native_one_shot_setup.sh`: one-shot native deploy dari Recovery ISO
- `export_qcow2_to_gz.sh`: export disk QEMU ke `.img.gz`
- `install_windows_auto.sh`: install Windows unattended di VM QEMU
- `start_windows_vm.sh`: start VM Windows mode normal
- `stop_windows_vm.sh`: stop VM Windows
- `droplet_one_shot_setup.sh`: one-shot setup mode QEMU
- `diagnose_rdp.sh`: diagnosa cepat masalah RDP

---

## Update Repo Saat Ada Perubahan Baru

Jalankan di droplet:

```bash
cd /root/auto-install-windows-BYKORASU
git remote -v
git pull --ff-only origin main
ls -la
```

Cek file penting:

```bash
ls -la export_qcow2_to_gz.sh
chmod +x export_qcow2_to_gz.sh
```

---

## Prasyarat Umum

Buka inbound port di DigitalOcean Cloud Firewall:
- TCP 3389 (RDP)
- TCP 5901 (VNC, hanya untuk mode QEMU installer)

---

## Mode A: Native Hard Drive (Lebih Ringan)

Penting:
- Jalankan dari Recovery ISO environment.
- Ini akan overwrite disk target.
- Pastikan image Windows Anda memang bootable dan sudah siap network + RDP.

### A1. Manual Native Deploy

```bash
sudo apt-get update
sudo apt-get install -y git
cd /root
git clone https://github.com/korasu-ho/auto-install-windows-BYKORASU.git
cd auto-install-windows-BYKORASU
chmod +x install_windows_native_disk.sh
```

Contoh deploy `.img.gz`:

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://contoh-domain.com/windows-server.img.gz' SOURCE_TYPE=gz ./install_windows_native_disk.sh
```

Contoh deploy dari Google Drive:

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://drive.google.com/file/d/FILE_ID/view?usp=sharing' SOURCE_TYPE=gz ./install_windows_native_disk.sh
```

Contoh deploy dari Mega:

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://mega.nz/file/XXXX#KEY' SOURCE_TYPE=gz ./install_windows_native_disk.sh
```

### A2. One-Shot Native Deploy

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://contoh-domain.com/windows-server.img.gz' SOURCE_TYPE=gz bash -c "$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_native_one_shot_setup.sh)"
```

### A3. Setelah Deploy Native Selesai

1. Di panel DigitalOcean, set boot ke `Boot from Hard Drive`.
2. Power cycle droplet.
3. Pastikan firewall buka TCP 3389.
4. RDP dari lokal ke `IP_DROPLET:3389`.

---

## Mode B: Nested VM QEMU

Mode ini memakai ISO installer resmi Microsoft untuk pilihan 1-3.

### B1. Manual QEMU Install

```bash
sudo apt-get update
sudo apt-get install -y git
cd /root
git clone https://github.com/korasu-ho/auto-install-windows-BYKORASU.git
cd auto-install-windows-BYKORASU
chmod +x install_windows_auto.sh start_windows_vm.sh stop_windows_vm.sh diagnose_rdp.sh droplet_one_shot_setup.sh
```

Contoh install pilihan 3 (Windows Server 2022):

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=3 ./install_windows_auto.sh
```

Pilihan `WIN_VERSION_CHOICE`:
- `1`: Windows Server 2016
- `2`: Windows Server 2019
- `3`: Windows Server 2022
- `4`: custom URL via `ISO_URL`

Contoh custom URL:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=4 ISO_URL='https://contoh-domain.com/windows-server.iso' ./install_windows_auto.sh
```

Contoh custom URL Google Drive:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=4 ISO_URL='https://drive.google.com/file/d/FILE_ID/view?usp=sharing' ./install_windows_auto.sh
```

Contoh custom URL Mega:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=4 ISO_URL='https://mega.nz/file/XXXX#KEY' ./install_windows_auto.sh
```

### B2. One-Shot QEMU Install

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=3 bash -c "$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_one_shot_setup.sh)"
```

### B3. Setelah Setup di VNC Selesai

1. Tunggu Windows setup sampai login/desktop.
2. Jalankan:

```bash
sudo ./stop_windows_vm.sh
sudo ./start_windows_vm.sh
```

3. RDP ke `IP_DROPLET:3389`.

---

## Migrasi dari QEMU (1-3) ke Native Hard Drive

Jika Anda sudah sukses install + RDP di mode QEMU, ini cara paling aman untuk pindah ke mode native yang lebih ringan.

### Step 1. Export Disk QEMU

```bash
cd /root/auto-install-windows-BYKORASU
chmod +x export_qcow2_to_gz.sh
sudo ./export_qcow2_to_gz.sh
```

Output default:
- `/opt/winvm/export/windows-from-qcow2.img.gz`

### Step 2. Siapkan URL untuk File Export

Opsi umum:
- Upload ke DO Spaces / S3 / server file Anda

Opsi cepat dari droplet aktif (sementara):

```bash
sudo apt-get update
sudo apt-get install -y apache2
sudo cp /opt/winvm/export/windows-from-qcow2.img.gz /var/www/html/
ls -lh /var/www/html/windows-from-qcow2.img.gz
```

Unduh dari PC lokal:
- `http://IP_DROPLET/windows-from-qcow2.img.gz`

Setelah selesai, hapus file publik:

```bash
sudo rm -f /var/www/html/windows-from-qcow2.img.gz
```

### Step 3. Deploy di Recovery ISO

Jika Anda masuk ke Recovery ISO pada droplet baru, repo biasanya belum ada. Jalankan bootstrap dulu:

```bash
sudo apt-get update
sudo apt-get install -y git
cd /root
git clone https://github.com/korasu-ho/auto-install-windows-BYKORASU.git
cd auto-install-windows-BYKORASU
chmod +x install_windows_native_disk.sh droplet_native_one_shot_setup.sh
```

Contoh dari URL:

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://url-anda/windows-from-qcow2.img.gz' SOURCE_TYPE=gz ./install_windows_native_disk.sh
```

Contoh dari file lokal:

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_FILE='/path/windows-from-qcow2.img.gz' SOURCE_TYPE=gz ./install_windows_native_disk.sh
```

Alternatif paling cepat (tanpa clone manual), langsung one-shot dari Recovery ISO:

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://url-anda/windows-from-qcow2.img.gz' SOURCE_TYPE=gz bash -c "$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_native_one_shot_setup.sh)"
```

Jika source di Google Drive (gdown):

Opsi otomatis (script handle gdown):

```bash
sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://drive.google.com/file/d/FILE_ID/view?usp=sharing' SOURCE_TYPE=gz ./install_windows_native_disk.sh
```

Opsi manual (download dulu):

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv
python3 -m venv /tmp/gdown-venv
/tmp/gdown-venv/bin/pip install --upgrade pip gdown
/tmp/gdown-venv/bin/gdown --fuzzy 'https://drive.google.com/file/d/FILE_ID/view?usp=sharing' -O /tmp/windows-from-qcow2.img.gz
sudo CONFIRM_DESTROY_DISK=YES IMAGE_FILE='/tmp/windows-from-qcow2.img.gz' SOURCE_TYPE=gz ./install_windows_native_disk.sh
```

### Step 4. Finalisasi Boot Native

1. Ubah boot ke `Boot from Hard Drive`.
2. Reboot/power cycle.
3. Pastikan TCP 3389 terbuka.
4. RDP ke `IP_DROPLET:3389`.

---

## Variabel Penting

### Untuk install_windows_auto.sh (QEMU)
- `WIN_ADMIN_PASSWORD`
- `WIN_VERSION_CHOICE`
- `ISO_URL`
- `ISO_PATH`
- `VM_CPUS` (default 4)
- `VM_RAM_MB` (default 6144)
- `DISK_GB` (default 64)
- `RDP_HOST_PORT` (default 3389)
- `VNC_DISPLAY` (default 1 -> port 5901)

### Untuk install_windows_native_disk.sh (Native)
- `CONFIRM_DESTROY_DISK=YES` (wajib)
- `IMAGE_URL` atau `IMAGE_FILE`
- `SOURCE_TYPE` (`auto`, `raw`, `gz`, `xz`)
- `TARGET_DISK` (default `/dev/vda`)

---

## Troubleshooting Cepat

### QEMU nyangkut / proses lama masih jalan

```bash
sudo ./stop_windows_vm.sh
sudo pkill -f qemu-system-x86_64 || true
sudo rm -f /opt/winvm/qemu-install.pid /opt/winvm/qemu-run.pid
```

### Port 3389 bentrok

```bash
sudo ss -ltnp | grep :3389
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' RDP_HOST_PORT=3390 WIN_VERSION_CHOICE=3 ./install_windows_auto.sh
```

Lalu RDP ke `IP_DROPLET:3390` dan buka TCP 3390 di firewall.

### Disk/partition error saat setup

```bash
sudo ./stop_windows_vm.sh
sudo rm -f /opt/winvm/winvm.qcow2 /opt/winvm/Autounattend.xml /opt/winvm/autounattend.iso
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' VM_MACHINE='pc' WIN_VERSION_CHOICE=3 ./install_windows_auto.sh
```

### Diagnosa RDP

```bash
chmod +x diagnose_rdp.sh
sudo ./diagnose_rdp.sh
```

---

## Catatan Keamanan

- Image Windows bisa berisi data sensitif.
- Hindari publish image terlalu lama di endpoint publik.
- Setelah transfer selesai, hapus file publik dan batasi firewall sesuai kebutuhan.

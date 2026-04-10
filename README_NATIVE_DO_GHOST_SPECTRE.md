# Ghost Spectre Native di DigitalOcean (Per Blok Siap Copas)

Panduan ini khusus untuk:
- Build image Ghost Spectre di Droplet 1 (builder)
- Deploy image ke Droplet 2 sebagai native boot (bukan QEMU runtime)

Alur mirip Windows 2022 Native, tapi untuk Ghost Spectre disarankan manual install di VNC dan wajib load driver VirtIO.

---

## Peringatan Penting

- Gunakan ISO Ghost Spectre dari sumber yang Anda percaya.
- Pastikan lisensi/aktivasi dan compliance penggunaan image sesuai tanggung jawab Anda.
- Deploy native akan overwrite disk target (`/dev/vda`).

---

## Arsitektur

- Droplet 1: Builder (Ubuntu normal boot dari Hard Drive)
- Droplet 2: Target native (tulis image saat Recovery ISO)

---

## Port yang perlu dibuka

- Droplet 1: TCP 5901 (sementara untuk VNC builder)
- Droplet 2: TCP 3389 (untuk RDP setelah native boot)

---

## BLOK 1 - Setup Droplet 1

Jalankan di Droplet 1 (Ubuntu normal, bukan Recovery):

```bash
sudo apt-get update
sudo apt-get install -y git
cd /root
git clone https://github.com/korasu-ho/auto-install-windows-BYKORASU.git
cd /root/auto-install-windows-BYKORASU
chmod +x build_do_compatible_image.sh export_do_compatible_image.sh
```

---

## BLOK 2 - Start Builder Ghost Spectre (Manual Mode)

Karena Ghost Spectre adalah custom ISO, gunakan mode manual:
- `AUTO_INSTALL=false`
- `WIN_VERSION_CHOICE=4` + `ISO_URL=...`
- `BUILDER_DISK_IF=ide` untuk jalur install paling stabil

Jalankan:

```bash
cd /root/auto-install-windows-BYKORASU
sudo AUTO_INSTALL=false WIN_VERSION_CHOICE=4 ISO_URL='URL_ISO_GHOST_SPECTRE' BUILDER_DISK_IF=ide VM_CPUS=4 VM_RAM_MB=6144 ./build_do_compatible_image.sh
```

Jika source ISO dari Mega atau Google Drive, install dependency dulu (selain `apt-get update`):

```bash
sudo apt-get install -y megatools python3 python3-venv
```

### Opsi A - Download ISO dari Mega

```bash
cd /opt/winvm
sudo megadl --path /opt/winvm 'URL_MEGA_GHOST_SPECTRE'
sudo ls -lh /opt/winvm
```

Setelah file ISO selesai terdownload, rename ke nama standar agar mudah:

```bash
sudo mv '/opt/winvm/NAMA_FILE_ISO_ASLI.iso' /opt/winvm/windows-custom.iso
ls -lh /opt/winvm/windows-custom.iso
```

### Opsi B - Download ISO dari Google Drive (gdown)

```bash
cd /opt/winvm
python3 -m venv /opt/winvm/.gdown-venv
/opt/winvm/.gdown-venv/bin/pip install --upgrade pip
/opt/winvm/.gdown-venv/bin/pip install gdown
/opt/winvm/.gdown-venv/bin/gdown --fuzzy 'URL_GDRIVE_GHOST_SPECTRE' -O /opt/winvm/windows-custom.iso
ls -lh /opt/winvm/windows-custom.iso
```

### Jalankan builder pakai ISO lokal yang sudah didownload

```bash
cd /root/auto-install-windows-BYKORASU
sudo AUTO_INSTALL=false WIN_VERSION_CHOICE=4 ISO_URL='https://local-placeholder.invalid/ghost.iso' ISO_PATH='/opt/winvm/windows-custom.iso' BUILDER_DISK_IF=ide VM_CPUS=4 VM_RAM_MB=6144 ./build_do_compatible_image.sh
```

Catatan:
- `ISO_URL` tetap wajib diisi untuk `WIN_VERSION_CHOICE=4`, tapi tidak akan dipakai jika `ISO_PATH` sudah ada.
- Pastikan path ISO lokal benar sebelum jalankan builder.

Pantau via VNC:
- `IP_DROPLET_1:5901`

---

## BLOK 3 - Manual Install di VNC (Wajib Load VirtIO)

Di layar setup Windows (manual):
1. Klik `Load driver`
2. Buka CD VirtIO
3. Load driver storage (coba urutan berikut):
   - `viostor\\w10\\amd64`
   - jika tidak cocok, coba `vioscsi\\w10\\amd64`
4. Setelah disk muncul, lanjut install normal

Setelah login pertama di Windows Ghost Spectre:
1. Install driver network `NetKVM`:
   - `NetKVM\\w10\\amd64`
2. Jalankan `virtio-win-guest-tools.exe` dari CD VirtIO
3. Pastikan network aktif dan internet bisa ping
4. Aktifkan RDP (jika belum aktif)
5. Shutdown Windows normal dari Start Menu

Catatan:
- Jangan export sebelum driver storage + network terpasang.
- Jika NIC belum jalan, cek Device Manager dan pastikan `Red Hat VirtIO Ethernet Adapter` aktif.

---

## BLOK 4 - Export Image di Droplet 1

```bash
cd /root/auto-install-windows-BYKORASU
sudo ./export_do_compatible_image.sh
ls -lh /opt/winvm/export/windows-do-compatible.img.gz
gzip -t /opt/winvm/export/windows-do-compatible.img.gz && echo GZIP_OK
```

---

## BLOK 5 - Publish Sementara dari Droplet 1

```bash
sudo apt-get update
sudo apt-get install -y apache2
sudo cp /opt/winvm/export/windows-do-compatible.img.gz /var/www/html/
ls -lh /var/www/html/windows-do-compatible.img.gz
```

---

## BLOK 6 - Deploy ke Droplet 2 (Recovery ISO)

Di panel DigitalOcean:
1. Set Droplet 2 ke Recovery ISO
2. Masuk SSH ke Droplet 2

Jalankan di Droplet 2:

```bash
sudo wget -O- http://IP_DROPLET_1/windows-do-compatible.img.gz | gunzip | sudo dd of=/dev/vda bs=16M conv=fsync status=progress
sync
sudo lsblk
sudo fdisk -l /dev/vda || true
```

---

## BLOK 7 - Finalisasi Boot Native di Droplet 2

Di panel DigitalOcean:
1. Ubah boot Droplet 2 ke Hard Drive
2. Power cycle

Lalu:
1. Pastikan firewall membuka TCP 3389
2. Test RDP ke `IP_DROPLET_2:3389`

Jika boot sukses tapi internet/RDP gagal:
1. Login via console DigitalOcean
2. Buka `ncpa.cpl` -> adapter VirtIO aktif -> `IPv4`
3. Isi IP/Subnet/Gateway manual sesuai info recovery console
4. DNS manual: `1.1.1.1` dan `8.8.8.8`
5. Tes `ipconfig /all`, `ping 1.1.1.1`, `ping google.com`

Opsi cepat:
- Jalankan script interaktif `example/windows-network-quickfix.cmd` (Run as Administrator) di Windows native.

---

## BLOK 8 - Cleanup File Publik di Droplet 1

```bash
sudo rm -f /var/www/html/windows-do-compatible.img.gz
```

---

## Cek Status Cepat Builder (Opsional)

```bash
cd /root/auto-install-windows-BYKORASU
sudo WIN_VERSION_CHOICE=4 ISO_URL='URL_ISO_GHOST_SPECTRE' ./build_do_compatible_image.sh --status
```

---

## Troubleshooting Singkat

Jika Droplet 2 gagal boot atau RDP gagal:
1. Ulangi BLOK 6 dan pastikan stream `dd` selesai 100 persen
2. Pastikan boot mode sudah kembali ke Hard Drive
3. Ulangi build manual dengan `BUILDER_DISK_IF=ide`
4. Pastikan driver `viostor/vioscsi` dan `NetKVM` benar-benar terpasang sebelum shutdown

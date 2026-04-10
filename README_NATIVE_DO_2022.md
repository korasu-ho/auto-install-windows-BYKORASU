# Windows 2022 Native di DigitalOcean (Per Blok Siap Copas)

Panduan ini khusus untuk:
- Build image Windows Server 2022 yang DO-compatible di Droplet 1
- Deploy image ke Droplet 2 sebagai native boot (bukan QEMU runtime)

Gunakan urutan blok dari atas ke bawah.

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

## BLOK 2 - Start Builder Windows 2022 (Pilihan 3)

Status terbaru (berdasarkan uji real):
- `AUTO_INSTALL=true` bisa gagal dengan error `ImageInstall` (disk/partition unattended).
- Jalur yang stabil: `AUTO_INSTALL=false` lalu load driver manual di VNC.

Update script terbaru:
- `AUTO_INSTALL=true` sekarang otomatis pakai mode disk installer yang lebih aman (`ide`) untuk pilihan 1-3.
- Driver VirtIO tetap di-inject untuk kompatibilitas native.

Jika ingin coba auto lagi (paling simpel), jalankan:

```bash
cd /root/auto-install-windows-BYKORASU
sudo AUTO_INSTALL=true WIN_VERSION_CHOICE=3 VM_CPUS=4 VM_RAM_MB=6144 ./build_do_compatible_image.sh
```

Jika auto masih gagal, langsung pakai jalur manual stabil di bawah.

Jalankan builder manual mode:

```bash
cd /root/auto-install-windows-BYKORASU
sudo AUTO_INSTALL=false WIN_VERSION_CHOICE=3 BUILDER_DISK_IF=ide VM_CPUS=4 VM_RAM_MB=6144 ./build_do_compatible_image.sh
```

Pantau via VNC:
- IP_DROPLET_1:5901

Di layar setup Windows (manual):
1. Klik `Load driver`
2. Buka CD VirtIO
3. Pilih driver storage `viostor` -> `2k22` -> `amd64`
4. Setelah disk muncul, lanjut install normal

Setelah login pertama di Windows:
1. Install driver network `NetKVM` (folder `2k22/amd64` bila diminta)
2. Jalankan `virtio-win-guest-tools.exe` dari CD VirtIO
3. Pastikan network dan RDP aktif
4. Shutdown Windows normal dari Start Menu

Jika builder lama masih nyangkut, reset cepat:

```bash
sudo pkill -f qemu-system-x86_64 || true
sudo rm -f /opt/winvm/qemu-do-builder.pid
cd /root/auto-install-windows-BYKORASU
sudo AUTO_INSTALL=false WIN_VERSION_CHOICE=3 BUILDER_DISK_IF=ide VM_CPUS=4 VM_RAM_MB=6144 ./build_do_compatible_image.sh
```

Catatan:
- Kombinasi `AUTO_INSTALL=false + BUILDER_DISK_IF=ide` saat ini paling konsisten untuk meloloskan setup.
- Hasil export tetap bisa dipakai native selama driver storage/network sudah terpasang sebelum shutdown.

---

## BLOK 3 - Saat Install Selesai di VNC

Saat sudah masuk desktop/login Windows di builder:
1. Verifikasi network aktif
2. Verifikasi RDP aktif
3. Shutdown Windows normal dari Start Menu

---

## BLOK 4 - Export Image di Droplet 1

```bash
cd /root/auto-install-windows-BYKORASU
sudo ./export_do_compatible_image.sh
ls -lh /opt/winvm/export/windows-do-compatible.img.gz
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
2. Test RDP ke IP_DROPLET_2:3389

### Catatan Penting Network (Jika DHCP Tidak Jalan)

Jika Windows native sudah boot tapi internet/RDP masih gagal, cek adapter `Red Hat VirtIO Ethernet Adapter`.
Pada beberapa kasus, koneksi baru aktif setelah set IPv4 manual sesuai data dari console recovery droplet.

Langkah cepat di Windows (native):
1. Buka `ncpa.cpl` -> klik kanan Ethernet VirtIO -> `Properties`.
2. Pilih `Internet Protocol Version 4 (TCP/IPv4)` -> `Properties`.
3. Isi manual dengan nilai yang sama seperti info network di recovery console droplet:
	- IP address
	- Subnet mask
	- Default gateway
4. DNS server isi manual:
	- Preferred DNS: `1.1.1.1`
	- Alternate DNS: `8.8.8.8`
5. Apply, lalu tes dari CMD:
	- `ipconfig /all`
	- `ping 1.1.1.1`
	- `ping google.com`

Jika ping sudah sukses, biasanya RDP ke port 3389 langsung normal.

Opsi cepat via script interaktif (tanpa banyak copy-paste command):
1. Siapkan file `example/windows-network-quickfix.cmd` ke Windows native (misalnya upload/download ke Desktop).
2. Jalankan `Command Prompt` as Administrator.
3. Run file tersebut, lalu isi prompt:
	- Interface name atau index (pilih adapter VirtIO yang aktif)
	- IPv4, Subnet Mask, Gateway (samakan dengan info recovery console droplet)
	- DNS otomatis diset ke `1.1.1.1` dan `8.8.8.8`
4. Script akan otomatis jalankan verifikasi `ipconfig` dan `ping`.

---

## BLOK 8 - Cleanup File Publik di Droplet 1

```bash
sudo rm -f /var/www/html/windows-do-compatible.img.gz
```

---

## Cek Status Cepat Builder (Opsional)

Jika build terasa lama atau ragu status:

```bash
cd /root/auto-install-windows-BYKORASU
sudo WIN_VERSION_CHOICE=3 ./build_do_compatible_image.sh --status
```

---

## Reuse Image Lama (Builder Baru Tanpa Install Ulang)

Jika image Windows lama sudah berisi perubahan penting (misalnya script network quick fix),
Anda bisa buat builder baru dari image existing tanpa install ulang dari ISO.

### 1) Stop proses QEMU lama

```bash
sudo pkill -f qemu-system-x86_64 || true
sudo rm -f /opt/winvm/qemu-do-builder.pid
```

### 2) Duplikasi image lama sebagai image v2 (opsional tapi disarankan)

```bash
sudo cp --sparse=always /opt/winvm/winvm-do-virtio.img /opt/winvm/winvm-do-virtio-v2.img
ls -lh /opt/winvm/winvm-do-virtio*.img
```

### 3) Boot image v2 langsung dari disk (bukan installer)

```bash
sudo qemu-system-x86_64 -name winvm-do-v2 -machine type=pc,accel=kvm:tcg -cpu host -smp 4 -m 6144 -drive file=/opt/winvm/winvm-do-virtio-v2.img,if=ide,format=raw,cache=writeback,discard=unmap -drive file=/opt/winvm/virtio-win.iso,media=cdrom,if=ide -boot order=c -netdev user,id=net0,hostfwd=tcp::3389-:3389 -device virtio-net-pci,netdev=net0 -vnc 0.0.0.0:1 -display none -daemonize -pidfile /opt/winvm/qemu-do-builder.pid
```

Pantau via VNC:
- `IP_DROPLET_1:5901`

Lalu login Windows, verifikasi perubahan, dan shutdown normal.

### 4) Export image v2

```bash
cd /root/auto-install-windows-BYKORASU
sudo RAW_IMG_PATH=/opt/winvm/winvm-do-virtio-v2.img OUTPUT_NAME=windows-do-compatible-v2.img.gz ./export_do_compatible_image.sh
ls -lh /opt/winvm/export/windows-do-compatible-v2.img.gz
gzip -t /opt/winvm/export/windows-do-compatible-v2.img.gz && echo GZIP_OK
```

### 5) Publish sementara dan deploy ulang ke Droplet 2

```bash
sudo cp /opt/winvm/export/windows-do-compatible-v2.img.gz /var/www/html/
```

Di Droplet 2 (Recovery ISO):

```bash
sudo wget -O- http://IP_DROPLET_1/windows-do-compatible-v2.img.gz | gunzip | sudo dd of=/dev/vda bs=16M conv=fsync status=progress
sync
sudo lsblk
sudo fdisk -l /dev/vda || true
```

Catatan:
- Metode ini cocok untuk "mount ulang" image existing ke builder baru.
- Tidak perlu install ulang Windows dari awal jika perubahan sudah ada di image lama.

---

## Troubleshooting Singkat

Jika Droplet 2 masih gagal boot native:
1. Ulangi deploy pada BLOK 6 (pastikan stream dd selesai 100 persen)
2. Pastikan boot mode sudah kembali ke Hard Drive
3. Jalankan ulang builder pakai fallback ide pada BLOK 2

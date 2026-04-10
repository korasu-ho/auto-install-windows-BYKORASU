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

Jalankan ini dulu (mode default virtio):

```bash
cd /root/auto-install-windows-BYKORASU
sudo AUTO_INSTALL=true WIN_VERSION_CHOICE=3 VM_CPUS=4 VM_RAM_MB=6144 ./build_do_compatible_image.sh
```

Pantau via VNC:
- IP_DROPLET_1:5901

Jika muncul error setup disk/partition unattended seperti ImageInstall, stop dan jalankan fallback ini:

```bash
sudo pkill -f qemu-system-x86_64 || true
sudo rm -f /opt/winvm/qemu-do-builder.pid
cd /root/auto-install-windows-BYKORASU
sudo AUTO_INSTALL=true WIN_VERSION_CHOICE=3 BUILDER_DISK_IF=ide VM_CPUS=4 VM_RAM_MB=6144 ./build_do_compatible_image.sh
```

Catatan:
- Fallback ide hanya untuk meloloskan installer.
- Script tetap attach VirtIO ISO dan menyiapkan driver agar aman untuk target native.

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

## Troubleshooting Singkat

Jika Droplet 2 masih gagal boot native:
1. Ulangi deploy pada BLOK 6 (pastikan stream dd selesai 100 persen)
2. Pastikan boot mode sudah kembali ke Hard Drive
3. Jalankan ulang builder pakai fallback ide pada BLOK 2

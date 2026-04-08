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
### Opsi paling mudah (Windows one-click push ke GitHub)
1. Double-click file `push_github_one_click.bat` di folder project.
2. Script akan otomatis:
- set git user/email (jika belum ada),
- commit perubahan,
- set remote ke repo GitHub,
- push ke branch `main`.
3. Jika diminta login GitHub saat push, pakai username + Personal Access Token.

Setelah push selesai, di droplet cukup clone:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/korasu-ho/auto-install-windows-BYKORASU.git
cd auto-install-windows-BYKORASU
chmod +x install_windows_auto.sh start_windows_vm.sh stop_windows_vm.sh
```

### Opsi manual
1. Upload file script ke droplet, lalu beri execute permission:

```bash
chmod +x install_windows_auto.sh start_windows_vm.sh stop_windows_vm.sh
```

### Opsi droplet one-shot (paling cepat dari server baru)
Jalankan langsung di droplet:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_one_shot_setup.sh)"
```

Contoh dengan password dan pilihan Windows Server 2022:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=3 bash -c "$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_one_shot_setup.sh)"
```

2. Jalankan installer unattended:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' ISO_URL='https://url-iso-windows-anda.iso' ./install_windows_auto.sh
```

Atau pakai pilihan cepat ISO official Microsoft:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' WIN_VERSION_CHOICE=3 ./install_windows_auto.sh
```

Pilihan `WIN_VERSION_CHOICE`:
- `1` = Windows Server 2016
- `2` = Windows Server 2019
- `3` = Windows Server 2022
- `4` = custom URL (wajib isi `ISO_URL`)

Jika ISO sudah Anda copy manual ke `/opt/winvm/windows.iso`, cukup:

```bash
sudo WIN_ADMIN_PASSWORD='PasswordKuatAnda!' ./install_windows_auto.sh
```

3. Akses proses install:
- VNC: `IP_DROPLET:5901`
- Setelah selesai install: RDP `IP_DROPLET:3389`

RDP sekarang dipaksa aktif otomatis saat first logon, termasuk:
- enable RDP,
- buka firewall remote desktop,
- allow TCP 3389 secara eksplisit,
- paksa service `TermService` auto-start,
- disable NLA untuk kompatibilitas client RDP.

4. Setelah install selesai, hentikan mode installer dan jalankan mode normal:

```bash
sudo ./stop_windows_vm.sh
sudo ./start_windows_vm.sh
```

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

- Jika VM berat/lambat, turunkan VM_CPUS dan/atau VM_RAM_MB.
- Jika install gagal, cek ISO Anda (wajib ISO bootable x64).

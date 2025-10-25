# PCD Filter — Godot + Python (UDP Video & Landmarks)

Project tugas **Pengolahan Citra Digital**: membuat filter **dasi / choker / kalung** yang menempel pada leher pengguna secara realtime.
Arsitektur: **Python** melakukan *computer vision* (MediaPipe + OpenCV), lalu mengirim:

* **Landmarks** (dagu, bahu kiri/kanan, estimasi base leher) via **UDP:5005**
* **Video** (frame JPEG 320×240 di-*base64*) via **UDP:5006**

**Godot** menampilkan video di UI dan menempelkan sprite aksesoris berdasarkan landmarks.

---

## Demo (alur tinggi)

```
Webcam → Python (OpenCV + MediaPipe)
  ├─ deteksi wajah/pose
  ├─ heuristik kerah (deteksi kemeja)
  ├─ kirim JSON landmarks  → UDP : 5005
  └─ kirim frame JPEG b64  → UDP : 5006
                         ↓
                 Godot (UI)
  ├─ UDPVideoClient terima video → tampil pada TextureRect (WebcamFeed)
  ├─ UDPClient terima landmarks   → emit signal ke Controller
  └─ Controller → pilih aksesoris (Auto/Dasi/Choker/Kalung) → atur posisi/scale Sprite2D
```

---

## Requirements

* **Windows 10/11** (tested)
* **Python 3.10 (64-bit)** + virtualenv
* **Godot 4.5 (atau 4.x)**
* Paket Python:

  * `mediapipe==0.10.14`
  * `opencv-python==4.12.0.88`
  * `numpy>=1.24`

> Paket tersedia di `requirements.txt`.

---

## Struktur Project

```
PCD-Filter/
├─ Assets/
│  └─ accessories/            ← gambar PNG transparan (tie/choker/necklace)
├─ Scenes/
│  └─ EthnicityDetectionScene.tscn
├─ Scripts/
│  ├─ EthnicityDetectionController.gd   ← controller UI + logika aksesoris
│  ├─ WebcamClient.gd                   ← UDP 5005 (landmarks) → signal
│  ├─ WebcamVideoClient.gd              ← UDP 5006 (jpeg b64) → TextureRect
│  └─ udp_webcam_server.py              ← Python server (CV + UDP)
├─ project.godot
├─ requirements.txt
└─ README.md
```

### Struktur Scene Godot (penting)

```
EthnicityDetection  (Control)  [script: EthnicityDetectionController.gd]
├─ MainContainer (Control)
│  ├─ CameraContainer/WebcamContainer/WebcamFeed (TextureRect) ← video tampil di sini
│  ├─ AccessoryLayer (Node2D)
│  │  ├─ TieSprite (Sprite2D)
│  │  ├─ ChokerSprite (Sprite2D)
│  │  └─ NecklaceSprite (Sprite2D)
│  └─ HUD
│     ├─ OptionButton  (Auto / Dasi / Choker / Kalung)
│     ├─ CheckBox      (Auto detect kemeja)
│     └─ Label         (status “UDP OK …”)
├─ UDPClient        (Node) [script: WebcamClient.gd, **group: udp_client**]
└─ UDPVideoClient   (Node) [script: WebcamVideoClient.gd]
```

> **Catatan:** `WebcamFeed` **tidak** memakai CameraServer (tidak ada `WebcamManager.gd`). Video datang dari UDP (Python).

---

## Setup (pertama kali)

### 1) Clone repo

```bash
# HTTPS
git clone https://github.com/<user>/<repo>.git
cd <repo>
```

### 2) Python venv + install dependency

**Windows (PowerShell):**

```powershell
py -3.10 -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
```

**Mac/Linux (opsional):**

```bash
python3.10 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

---

## Cara Menjalankan

### 1) Jalankan server Python (harus duluan)

```powershell
.\.venv\Scripts\activate
cd scripts
python udp_webcam_server.py
```

Yang terjadi:

* Python membuka webcam, menampilkan **preview debug** kecil,
* Mengirim **landmarks** ke **UDP:5005**,
* Mengirim **frame JPEG (320×240)** ke **UDP:5006**.

### 2) Jalankan Godot

* Buka folder project di Godot.
* Run `Scenes/EthnicityDetectionScene.tscn`.
* **WebcamFeed** menampilkan video dari Python.
* Label status akan berbunyi `UDP OK | ts=...` saat data masuk.
* Pilih mode **Auto/Dasi/Choker/Kalung** dari OptionButton.

---

## Aset Aksesoris (PNG)

Letakkan di `Assets/accessories/`:

* `dasi.png` (≈ 300×800, simpul di tengah, 20–30% dari atas, background transparan)
* `choker.png` (≈ 700×120, pita tipis horizontal, transparan)
* `kalung.png` (≈ 700×500, bentuk U + liontin opsional, transparan)

Assign:
`TieSprite.texture = dasi.png`, `ChokerSprite.texture = choker.png`, `NecklaceSprite.texture = kalung.png`.

---

## Port & Protokol

* **UDP 5005**: Landmarks (JSON), contoh payload:

  ```json
  {
    "ts": 1761382299.84,
    "chin": [x,y],
    "neck_base": [x,y],
    "left_shoulder": [x,y],
    "right_shoulder": [x,y],
    "wearing_shirt_collar": true
  }
  ```

* **UDP 5006**: Video (JSON) dengan JPEG base64:

  ```json
  {
    "w": 320, "h": 240,
    "jpg_b64": "<base64-jpeg>"
  }
  ```

---

## Troubleshooting

* **Video tidak muncul di Godot**

  * Pastikan Python `udp_webcam_server.py` sedang berjalan.
  * Pastikan node `UDPVideoClient` aktif dan `video_rect_path` menunjuk ke `WebcamFeed`.
  * Cek Output Godot: tidak ada error `UDP video bind failed at 5006`.

* **Landmarks tidak masuk**

  * Node `UDPClient` harus memakai **`WebcamClient.gd`** dan tergabung dalam **Group `udp_client`**.
  * Controller menghubungkan sinyal `landmarks_received` dari node dalam group itu.

* **Python error `_src.empty()` pada `cv::cvtColor`**

  * Sudah dipatch: ROI di-*clip* agar tidak kosong. Pastikan file Python di repo adalah versi terbaru.

* **Webcam tidak bisa dipakai Godot**

  * **Normal**: kamera hanya dipegang Python (kita streaming ke Godot). Jangan pakai `WebcamManager.gd`.

* **Pylance di VS Code “cv2/mediapipe not resolved”**

  * Pilih interpreter ke `.venv`: *Python: Select Interpreter* → `...\.venv\Scripts\python.exe`.
  * Atau restart Pylance.

---

## Progress Saat Ini ✅

* [x] **Arsitektur Mode B**: Python pegang kamera, Godot konsumsi UDP video + landmarks.
* [x] **Python**:

  * Capture webcam (640×480)
  * MediaPipe FaceMesh + Pose (model_complexity=0 → ringan)
  * Heuristik kerah kemeja (aman dari ROI kosong)
  * Kirim **landmarks (JSON/UDP:5005)**
  * Kirim **video JPEG 320×240 (JSON/UDP:5006)**
* [x] **Godot**:

  * `WebcamVideoClient.gd` decode base64 → tampil ke TextureRect (`WebcamFeed`)
  * `WebcamClient.gd` emit `landmarks_received`
  * `EthnicityDetectionController.gd`:

    * pilih mode **Auto/Dasi/Choker/Kalung**
    * skala aksesori ∝ jarak bahu
    * anchor di base leher + offset halus
    * rotasi dasi mengikuti garis bahu
* [x] **Aset placeholder** dapat diganti kapan saja (PNG transparan).
* [x] **README + requirements + .gitignore** siap kolaborasi.

### TODO (next)

* [ ] Fine tuning posisi/scale offset untuk tiap aksesori (sesuaikan PNG final).
* [ ] Tambah tombol **screenshot** (save frame + filter).
* [ ] Opsi mirror video (kiri-kanan).
* [ ] UI polishing (indikator FPS / status koneksi UDP).

---

## Workflow Kolaborasi (Git)

### 1) Clone

```bash
git clone https://github.com/<user>/<repo>.git
cd <repo>
```

### 2) Buat branch baru untuk tiap orang/fitur

```bash
# update dari remote dulu
git checkout main
git pull origin main

# buat branch kerja kamu
git checkout -b feat/<namafitur>-<namamu>
# contoh: git checkout -b feat/screenshot-naomi
```

### 3) Commit & push ke branch masing-masing

```bash
git add .
git commit -m "feat: tambah tombol screenshot & simpan PNG"
git push -u origin feat/<namafitur>-<namamu>
```

### 4) Buka Pull Request (PR)

* Buka GitHub repo → muncul banner “Compare & pull request”.
* Pilih base: **main**, compare: **feat/<namafitur>-<namamu>**.
* Isi deskripsi singkat (apa yang berubah, cara test).
* Assign reviewer teman/dosen bila perlu.

### 5) Update branch kalau main berubah

```bash
git checkout main
git pull origin main

git checkout feat/<namafitur>-<namamu>
git rebase main          # atau: git merge main
# selesaikan konflik, lalu:
git push -f              # kalau habis rebase
```

### 6) Tips Commit

* Gunakan pesan yang jelas: `feat: ...`, `fix: ...`, `docs: ...`, `chore: ...`.
* Satu commit fokus pada satu perubahan kecil.

---

## Cara Jalanin Ulang dari Nol (Ringkasan 5 langkah)

```powershell
git clone https://github.com/<user>/<repo>.git
cd <repo>
py -3.10 -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
python scripts/udp_webcam_server.py   # jalankan dulu
```

Buka Godot → run `Scenes/EthnicityDetectionScene.tscn`.

---

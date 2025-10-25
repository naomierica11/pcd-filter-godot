import cv2, socket, json, time, math, base64
import numpy as np
import mediapipe as mp

HOST = "127.0.0.1"
PORT_LANDMARK = 5005   # sama dengan Godot (landmark)
PORT_VIDEO    = 5006   # port baru untuk frame video

sock_lm = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock_vd = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

mp_face = mp.solutions.face_mesh
mp_pose = mp.solutions.pose

def lm_xy(landmark, w, h):
    return (int(landmark.x * w), int(landmark.y * h))

def distance(a, b):
    return math.hypot(a[0]-b[0], a[1]-b[1])

def py(v):
    if v is None: return None
    if isinstance(v, (tuple, list)): return [int(v[0]), int(v[1])]
    if isinstance(v, (np.bool_, bool)): return bool(v)
    if isinstance(v, (np.integer,)): return int(v)
    if isinstance(v, (np.floating,)): return float(v)
    return v

cap = cv2.VideoCapture(0)
cap.set(cv2.CAP_PROP_FRAME_WIDTH,  640)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

face = mp_face.FaceMesh(
    static_image_mode=False, max_num_faces=1, refine_landmarks=True,
    min_detection_confidence=0.5, min_tracking_confidence=0.5
)
pose = mp_pose.Pose(
    static_image_mode=False, model_complexity=0,
    min_detection_confidence=0.5, min_tracking_confidence=0.5
)

last_send = 0.0
frame_i = 0

try:
    while True:
        ok, frame = cap.read()
        if not ok: break
        h, w = frame.shape[:2]
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # --- Face & Pose ---
        chin = neck_base = l_sh = r_sh = None

        face_res = face.process(rgb)
        if face_res.multi_face_landmarks:
            f = face_res.multi_face_landmarks[0]
            chin = lm_xy(f.landmark[152], w, h)  # dagu

        pose_res = pose.process(rgb)
        if pose_res.pose_landmarks:
            pl = pose_res.pose_landmarks.landmark
            l_sh = lm_xy(pl[mp_pose.PoseLandmark.LEFT_SHOULDER],  w, h)
            r_sh = lm_xy(pl[mp_pose.PoseLandmark.RIGHT_SHOULDER], w, h)
            if l_sh and r_sh:
                mid = ((l_sh[0]+r_sh[0])//2, (l_sh[1]+r_sh[1])//2)
                neck_base = (mid[0], mid[1] - int(0.08*h))

        # --- heuristik kerah sederhana ---
        wearing_shirt_collar = False
        if chin and l_sh and r_sh:
            y0 = min(max(chin[1]+10, 0), h-1)
            y1 = min(chin[1]+60, h-1)
            x0 = max(min(chin[0]-50, w-1), 0)
            x1 = min(chin[0]+50, w-1)
            roi = frame[y0:y1, x0:x1]
            # Cek ROI valid terlebih dahulu
            if roi is not None and roi.size > 0:
                roi_gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
                edges = cv2.Canny(roi_gray, 60, 120)

                if edges.shape[1] > 0:  # pastikan ada kolom
                    cols = edges.sum(axis=0)
                    left_energy  = cols[:cols.size//2].sum()
                    right_energy = cols[cols.size//2:].sum()
                    sd = distance(l_sh, r_sh) + 1e-6
                    wearing_shirt_collar = (left_energy > 2000 and right_energy > 2000 and sd > 120)
                else:
                    wearing_shirt_collar = False
            else:
                wearing_shirt_collar = False


        now = time.time()

        # --- kirim LANDMARK (20 Hz) ---
        if now - last_send > 0.05:
            packet = {
                "ts": float(now),
                "chin": py(chin),
                "neck_base": py(neck_base),
                "left_shoulder": py(l_sh),
                "right_shoulder": py(r_sh),
                "wearing_shirt_collar": bool(wearing_shirt_collar),
            }
            sock_lm.sendto(json.dumps(packet).encode("utf-8"), (HOST, PORT_LANDMARK))
            last_send = now

        # --- kirim FRAME JPEG (base64) ukuran kecil ---
        small = cv2.resize(frame, (320, 240))
        ok_jpg, enc = cv2.imencode(".jpg", small, [int(cv2.IMWRITE_JPEG_QUALITY), 75])
        if ok_jpg:
            b64 = base64.b64encode(enc.tobytes()).decode("ascii")
            video_msg = {"w": 320, "h": 240, "jpg_b64": b64}
            sock_vd.sendto(json.dumps(video_msg).encode("utf-8"), (HOST, PORT_VIDEO))

        # opsional: preview untuk debug
        cv2.imshow("Python Preview (debug)", small)
        if cv2.waitKey(1) == 27:  # ESC
            break

except KeyboardInterrupt:
    pass
finally:
    cap.release()
    cv2.destroyAllWindows()
    sock_lm.close()
    sock_vd.close()

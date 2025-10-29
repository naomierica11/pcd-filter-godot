# udp_webcam_server.py
import cv2, time, json, math, socket, base64, numpy as np
import mediapipe as mp

HOST = "127.0.0.1"
PORT_LANDMARK = 5005
PORT_VIDEO = 5006

cap = cv2.VideoCapture(0)
cap.set(cv2.CAP_PROP_FRAME_WIDTH,  640)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

sock_lm = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock_vd = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

mp_face = mp.solutions.face_mesh
mp_pose = mp.solutions.pose

face = mp_face.FaceMesh(
    max_num_faces=1,
    refine_landmarks=True,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)
pose = mp_pose.Pose(
    model_complexity=1,
    enable_segmentation=False,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)

def ema_pair(prev, curr, a=0.25):
    if prev is None: return curr
    return [a*curr[0] + (1-a)*prev[0], a*curr[1] + (1-a)*prev[1]]

ema_neck = None
ema_angle = None
ema_scale = None
last_send = 0.0

try:
    while True:
        ok, frame = cap.read()
        if not ok: break
        h, w = frame.shape[:2]
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        chin = l_sh = r_sh = None

        # ---- Face (chin) ----
        fres = face.process(rgb)
        if fres.multi_face_landmarks:
            f = fres.multi_face_landmarks[0]
            chin_ids = [152, 175, 148]  # dagu & sekitarnya
            cx = sum(f.landmark[i].x for i in chin_ids)/len(chin_ids)
            cy = sum(f.landmark[i].y for i in chin_ids)/len(chin_ids)
            chin = [cx, cy]

        # ---- Pose (shoulders) ----
        pres = pose.process(rgb)
        if pres.pose_landmarks:
            pl = pres.pose_landmarks.landmark
            l = pl[mp_pose.PoseLandmark.LEFT_SHOULDER]
            r = pl[mp_pose.PoseLandmark.RIGHT_SHOULDER]
            l_sh = [l.x, l.y]
            r_sh = [r.x, r.y]

        neck_anchor = None
        angle = None
        scale = None
        shoulder_w = None

        if chin and l_sh and r_sh:
            mid = [(l_sh[0]+r_sh[0])/2.0, (l_sh[1]+r_sh[1])/2.0]
            # blend chin→mid-shoulder (turunin dikit biar pas di leher)
            neck_ratio = 0.30
            neck_anchor = [chin[0]*(1-neck_ratio)+mid[0]*neck_ratio,
                           chin[1]*(1-neck_ratio)+mid[1]*neck_ratio]

            vx, vy = (r_sh[0]-l_sh[0]), (r_sh[1]-l_sh[1])
            angle = math.atan2(vy, vx)                # radian
            shoulder_w = math.hypot(vx, vy)           # ~ skala lebar bahu
            scale = shoulder_w * 1.00                  # konstanta bisa dikalibrasi

            # smoothing ringan
            ema_neck = ema_pair(ema_neck, neck_anchor, 0.25)
            neck_anchor = ema_neck
            ema_angle = angle if ema_angle is None else 0.2*angle + 0.8*ema_angle
            angle = ema_angle
            ema_scale = scale if ema_scale is None else 0.3*scale + 0.7*ema_scale
            scale = ema_scale

        # ---- Heuristik sederhana "collared shirt?" untuk demo (tanpa training) ----
        wearing_shirt_collar = False
        if chin and l_sh and r_sh:
            chin_px = (int(chin[0]*w), int(chin[1]*h))
            l_px = (int(l_sh[0]*w), int(l_sh[1]*h))
            r_px = (int(r_sh[0]*w), int(r_sh[1]*h))
            roi_w = int(math.hypot(l_px[0]-r_px[0], l_px[1]-r_px[1]) * 0.6)
            roi_h = int(abs(chin_px[1] - (l_px[1]+r_px[1])/2) * 0.4)
            if roi_w>10 and roi_h>10:
                rx = max(0, min(int(chin_px[0]-roi_w/2), w-roi_w))
                ry = max(0, min(int(chin_px[1]+roi_h*0.2), h-roi_h))
                roi = frame[ry:ry+roi_h, rx:rx+roi_w]
                if roi.size>0:
                    hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
                    white_mask = cv2.inRange(hsv, np.array([0,0,200]), np.array([180,30,255]))
                    edges = cv2.Canny(cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY), 50, 150)
                    area = roi.shape[0]*roi.shape[1]
                    wearing_shirt_collar = (cv2.countNonZero(white_mask)>area*0.10 and
                                            cv2.countNonZero(edges)>area*0.05)

        # ---- kirim landmark (±15Hz) ----
        now = time.time()
        if now - last_send > 0.066:
            packet = {
                "ts": now,
                "neck_anchor": neck_anchor,       # [x,y] normalized
                "angle": angle,                   # radian
                "scale": scale,                   # ~ shoulder width
                "shoulder_width": shoulder_w,
                "wearing_shirt_collar": bool(wearing_shirt_collar),
                "chin": chin, "left_shoulder": l_sh, "right_shoulder": r_sh,
                "frame_size": [w, h]
            }
            sock_lm.sendto(json.dumps(packet).encode("utf-8"), (HOST, PORT_LANDMARK))
            last_send = now
            # debug log:
            # print(packet)

        # ---- video jpeg kecil ----
        small = cv2.resize(frame, (320, 240))
        ok_jpg, enc = cv2.imencode(".jpg", small, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
        if ok_jpg:
            b64 = base64.b64encode(enc.tobytes()).decode("ascii")
            sock_vd.sendto(json.dumps({"w": 320, "h": 240, "jpg_b64": b64}).encode("utf-8"),
                           (HOST, PORT_VIDEO))

        # preview debug
        dbg = small.copy()
        if l_sh: cv2.circle(dbg,(int(l_sh[0]*320),int(l_sh[1]*240)),4,(0,0,255),-1)
        if r_sh: cv2.circle(dbg,(int(r_sh[0]*320),int(r_sh[1]*240)),4,(0,0,255),-1)
        if neck_anchor: cv2.circle(dbg,(int(neck_anchor[0]*320),int(neck_anchor[1]*240)),5,(255,0,0),-1)
        cv2.imshow("Preview (BLUE=neck, RED=shoulders)", dbg)
        if cv2.waitKey(1)==27: break
except KeyboardInterrupt:
    pass
finally:
    cap.release(); cv2.destroyAllWindows(); sock_lm.close(); sock_vd.close()

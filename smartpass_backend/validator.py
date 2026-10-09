import cv2
from deepface import DeepFace
import requests
import time
import json

API_URL = "http://127.0.0.1:8000"

face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
qr_detector = cv2.QRCodeDetector()

def draw_centered_text(img, text, scale, thickness, color, y_offset=0):
    """ Функция для идеального центрирования огромного текста """
    font = cv2.FONT_HERSHEY_SIMPLEX
    text_size = cv2.getTextSize(text, font, scale, thickness)[0]
    text_x = (img.shape[1] - text_size[0]) // 2
    text_y = (img.shape[0] + text_size[1]) // 2 + y_offset
    cv2.putText(img, text, (text_x, text_y), font, scale, color, thickness)

def show_fullscreen_popup(cap, title, subtitle, is_success):
    """ ПОЛНОЭКРАННАЯ плашка на 3 секунды """
    ret, frame = cap.read()
    if not ret: return
    frame = cv2.flip(frame, 1)
    h, w, _ = frame.shape
    
    # Создаем цветную заливку на весь экран
    overlay = frame.copy()
    bg_color = (0, 200, 0) if is_success else (0, 0, 200) # Зеленый или Красный
    cv2.rectangle(overlay, (0, 0), (w, h), bg_color, -1)
    
    # Делаем заливку полупрозрачной (80% цвета, 20% камеры)
    cv2.addWeighted(overlay, 0.8, frame, 0.2, 0, frame)
    
    # Рисуем огромный текст по центру
    draw_centered_text(frame, title, scale=2.0, thickness=5, color=(255, 255, 255), y_offset=-40)
    draw_centered_text(frame, subtitle, scale=1.2, thickness=3, color=(255, 255, 255), y_offset=40)
    
    cv2.imshow("SmartPass Validator", frame)
    cv2.waitKey(3000)

def extract_pass_info(res_data):
    """ Извлекаем данные о тарифе """
    # Выводим в консоль, чтобы ты видел, что реально шлет бэкенд
    print("Ответ сервера:", res_data) 
    
    rem_trips = res_data.get('remaining_trips')
    exp_date = res_data.get('expires_at')
    balance = res_data.get('balance')

    if rem_trips is not None:
        return f"Trips left: {rem_trips}"
    elif exp_date is not None:
        date_str = str(exp_date).split('T')[0]
        return f"Unlimited till: {date_str}"
    elif balance is not None:
        return f"Balance: {balance} KGS"
    else:
        return "Access Granted"

def main():
    print("🚀 Запуск УМНОГО валидатора (с задержкой фиксации)...")
    cap = cv2.VideoCapture(0)

    # Настройки "удержания" лица
    FRAMES_TO_LOCK = 10 # Сколько кадров нужно держать лицо (около 1 сек)
    stable_frames = 0

    while True:
        ret, frame = cap.read()
        if not ret: break
        frame = cv2.flip(frame, 1)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        h_img, w_img, _ = frame.shape
        
        # 1. QR КОД
        data, bbox, _ = qr_detector.detectAndDecode(frame)
        if data:
            try:
                qr_json = json.loads(data)
                response = requests.post(f"{API_URL}/qr/validate/", json=qr_json)
                res_data = response.json()
                
                if response.status_code == 200:
                    msg = extract_pass_info(res_data)
                    show_fullscreen_popup(cap, "SUCCESS!", msg, True)
                else:
                    detail = res_data.get('detail', 'Access Denied')
                    show_fullscreen_popup(cap, "DECLINED!", str(detail), False)
            except Exception:
                show_fullscreen_popup(cap, "ERROR", "Invalid QR", False)
            
            stable_frames = 0 # Сбрасываем счетчик лица
            time.sleep(1.0)
            continue

        # 2. РАСПОЗНАВАНИЕ ЛИЦА (С ЗАДЕРЖКОЙ)
        faces = face_cascade.detectMultiScale(gray, 1.3, 5)
        
        face_detected_this_frame = False
        if len(faces) > 0:
            (x, y, w_f, h_f) = max(faces, key=lambda rect: rect[2] * rect[3])
            
            # Если лицо достаточно близко к камере
            if w_f > 130 and h_f > 130:
                face_detected_this_frame = True
                stable_frames += 1
                
                # Рисуем рамку
                cv2.rectangle(frame, (x, y), (x+w_f, y+h_f), (0, 255, 255), 2)
                
                # РИСУЕМ ПОЛОСУ ЗАГРУЗКИ ФИКСАЦИИ (Lock-on bar)
                progress = int((stable_frames / FRAMES_TO_LOCK) * w_f)
                cv2.rectangle(frame, (x, y - 15), (x + progress, y - 5), (0, 255, 0), -1)
                cv2.putText(frame, "Hold still...", (x, y - 20), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
                
                # Если удержали лицо нужное время - СТРЕЛЯЕМ!
                if stable_frames >= FRAMES_TO_LOCK:
                    cv2.putText(frame, "ANALYZING...", (x, y - 20), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
                    cv2.imshow("SmartPass Validator", frame)
                    cv2.waitKey(10)
                    
                    try:
                        result = DeepFace.represent(img_path=frame, model_name="ArcFace", enforce_detection=False)
                        vector = result[0]["embedding"]
                        response = requests.post(f"{API_URL}/recognize/", json={"face_vector": vector})
                        res_data = response.json()
                        
                        if response.status_code == 200:
                            msg = extract_pass_info(res_data)
                            show_fullscreen_popup(cap, "SUCCESS!", msg, True)
                        else:
                            detail = res_data.get('detail', 'Access Denied')
                            show_fullscreen_popup(cap, "DECLINED!", "Not Recognized / No Funds", False)
                    except Exception as e:
                        print("Ошибка DeepFace:", e)
                    
                    stable_frames = 0 # Сбрасываем после отправки
                    time.sleep(1.0) 

        # Если лицо пропало из кадра - сбрасываем таймер "пулемета"
        if not face_detected_this_frame:
            stable_frames = 0
            cv2.putText(frame, "Show QR or Look at Camera", (30, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (200, 200, 200), 2)

        cv2.imshow("SmartPass Validator", frame)
        if cv2.waitKey(1) & 0xFF == 27:
            break

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
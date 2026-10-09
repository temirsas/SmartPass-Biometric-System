import os
from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.orm import Session
from sqlalchemy import text
from datetime import datetime, timedelta
import pyotp
from fastapi.middleware.cors import CORSMiddleware
from deepface import DeepFace
from pydantic import BaseModel 

from app.database import engine, Base, SessionLocal
import app.models as models
import app.schemas as schemas


with engine.connect() as conn:
    conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector;"))
    conn.commit()
models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="SmartPass Billing System")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

PRICES = {
    "unlimited_1": 50.0,
    "unlimited_7": 250.0,
    "unlimited_30": 800.0,
    "ride_10": 150.0
}

def get_db():
    db = SessionLocal()
    try: yield db
    finally: db.close()


class TopUpRequest(BaseModel):
    user_id: int
    amount: float


def process_smart_payment(user_id: int, db: Session, method: str):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    now = datetime.utcnow()
    
    active_unlimited = db.query(models.Subscription).filter(
        models.Subscription.user_id == user_id,
        models.Subscription.sub_type.like("unlimited_%"),
        models.Subscription.expires_at > now,
        models.Subscription.is_active == True
    ).first()
    
    if active_unlimited:
        new_tx = models.Transaction(user_id=user_id, amount=0, payment_method=f"{method}_unlimited")
        db.add(new_tx)
        db.commit()
        return {"status": "success", "message": "Проезд по безлимитному тарифу"}

    ride_pack = db.query(models.Subscription).filter(
        models.Subscription.user_id == user_id,
        models.Subscription.sub_type == "ride_10",
        models.Subscription.rides_left > 0,
        models.Subscription.is_active == True
    ).first()
    
    if ride_pack:
        ride_pack.rides_left -= 1
        new_tx = models.Transaction(user_id=user_id, amount=0, payment_method=f"{method}_ride_pack")
        db.add(new_tx)
        db.commit()
        return {"status": "success", "message": f"Поездка списана с пакета. Осталось: {ride_pack.rides_left}"}

    FARE = 17.0
    if user.balance >= FARE:
        user.balance -= FARE
        new_tx = models.Transaction(user_id=user_id, amount=FARE, payment_method=method)
        db.add(new_tx)
        db.commit()
        return {"status": "success", "message": f"Списано {FARE} сом. Баланс: {user.balance}"}
    
    raise HTTPException(status_code=402, detail="Недостаточно средств")


@app.post("/users/", response_model=schemas.UserResponse)
def create_user(user: schemas.UserCreate, db: Session = Depends(get_db)):
    existing_user = db.query(models.User).filter(models.User.phone == user.phone).first()
    if existing_user:
        return existing_user
        
    new_user = models.User(phone=user.phone, balance=100.0) 
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user


@app.post("/users/topup/")
def topup_balance(req: TopUpRequest, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == req.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    if req.amount <= 0:
        raise HTTPException(status_code=400, detail="Сумма должна быть больше нуля")
    
    user.balance += req.amount
    
    new_tx = models.Transaction(user_id=user.id, amount=req.amount, payment_method="topup_card")
    db.add(new_tx)
    db.commit()
    return {"status": "success", "message": f"Баланс пополнен на {req.amount} сом", "new_balance": user.balance}

@app.post("/subscriptions/purchase/")
def purchase_subscription(sub: schemas.SubscriptionPurchase, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == sub.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    price = PRICES.get(sub.sub_type)
    if price is None:
        raise HTTPException(status_code=400, detail="Неверный тип тарифа")

    if user.balance < price:
        raise HTTPException(status_code=400, detail=f"Недостаточно средств. Нужно {price} сом, у вас {user.balance} сом")

    user.balance -= price
    now = datetime.utcnow()
    expires = None
    rides = 0
    
    if sub.sub_type == "unlimited_1": expires = now + timedelta(days=1)
    elif sub.sub_type == "unlimited_7": expires = now + timedelta(days=7)
    elif sub.sub_type == "unlimited_30": expires = now + timedelta(days=30)
    elif sub.sub_type == "ride_10": rides = 10
    
    new_sub = models.Subscription(
        user_id=sub.user_id, 
        sub_type=sub.sub_type, 
        expires_at=expires, 
        rides_left=rides
    )
    new_tx = models.Transaction(user_id=user.id, amount=price, payment_method=f"purchase_{sub.sub_type}")
    
    db.add(new_sub)
    db.add(new_tx)
    db.commit()
    return {"status": "success", "message": f"Тариф {sub.sub_type} активирован"}

@app.post("/recognize/")
def recognize_face(req: schemas.RecognizeRequest, db: Session = Depends(get_db)):
    THRESHOLD = 0.4 
    closest = db.query(
        models.Biometric, 
        models.Biometric.face_vector.cosine_distance(req.face_vector).label('distance')
    ).order_by(models.Biometric.face_vector.cosine_distance(req.face_vector)).first()

    if closest and closest.distance < THRESHOLD:
        return process_smart_payment(closest.Biometric.user_id, db, "face")
    
    raise HTTPException(status_code=404, detail="Лицо не узнано")

@app.post("/qr/validate/")
def validate_qr(req: schemas.QRValidateRequest, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == req.user_id).first()
    if not user: raise HTTPException(status_code=404, detail="User not found")
    
    totp = pyotp.TOTP(user.totp_secret)
    if totp.verify(req.totp_code):
        return process_smart_payment(user.id, db, "qr")
    
    raise HTTPException(status_code=403, detail="QR просрочен")

@app.post("/biometrics/upload/")
async def upload_biometrics(
    user_id: int = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    temp_path = f"temp_{user_id}.jpg"
    with open(temp_path, "wb") as buffer:
        buffer.write(await file.read())
    try:
        result = DeepFace.represent(img_path=temp_path, model_name="ArcFace", enforce_detection=True)
        vector = result[0]["embedding"]
        existing = db.query(models.Biometric).filter(models.Biometric.user_id == user_id).first()
        if existing:
            existing.face_vector = vector
        else:
            new_bio = models.Biometric(user_id=user_id, face_vector=vector)
            db.add(new_bio)
        db.commit()
        return {"status": "success"}
    except Exception:
        raise HTTPException(status_code=400, detail="Лицо не найдено на фото")
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)
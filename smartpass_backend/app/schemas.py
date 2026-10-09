from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

class UserCreate(BaseModel):
    phone: str

class UserResponse(BaseModel):
    id: int
    phone: str
    balance: float
    totp_secret: str 
    class Config:
        from_attributes = True

class BiometricCreate(BaseModel):
    user_id: int
    face_vector: List[float]

class RecognizeRequest(BaseModel):
    face_vector: List[float]

class QRValidateRequest(BaseModel):
    user_id: int
    totp_code: str


class SubscriptionPurchase(BaseModel):
    user_id: int
    sub_type: str 
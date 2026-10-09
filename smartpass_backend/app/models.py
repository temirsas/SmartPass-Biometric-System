from sqlalchemy import Column, Integer, String, Float, Boolean, ForeignKey, DateTime, Enum
from sqlalchemy.sql import func
from pgvector.sqlalchemy import Vector
from app.database import Base
import pyotp
import enum

class SubscriptionType(enum.Enum):
    UNLIMITED_1 = "unlimited_1" 
    UNLIMITED_3 = "unlimited_3" 
    UNLIMITED_7 = "unlimited_7" 
    UNLIMITED_30 = "unlimited_30"
    RIDE_10 = "ride_10"          

class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    phone = Column(String, unique=True, index=True)
    balance = Column(Float, default=0.0)
    is_active = Column(Boolean, default=True)
    totp_secret = Column(String, default=pyotp.random_base32)

class Subscription(Base):
    __tablename__ = "subscriptions"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    sub_type = Column(String) 
    rides_left = Column(Integer, default=0) 
    expires_at = Column(DateTime(timezone=True)) 
    is_active = Column(Boolean, default=True)

class Biometric(Base):
    __tablename__ = "biometrics"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    face_vector = Column(Vector(512)) 
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Transaction(Base):
    __tablename__ = "transactions"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    amount = Column(Float) 
    payment_method = Column(String) 
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
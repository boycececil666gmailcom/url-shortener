from datetime import datetime

from pydantic import BaseModel, HttpUrl


class ShortenRequest(BaseModel):
    long_url: HttpUrl


class URLCreateResponse(BaseModel):
    short_url: int
    long_url: str
    created_at: datetime


class URLLookupResponse(BaseModel):
    short_url: int
    long_url: str
    created_at: datetime

from datetime import datetime

from pydantic import BaseModel, HttpUrl


class ShortenRequest(BaseModel):
    long_url: HttpUrl


class ShortenResponse(BaseModel):
    short_code: int
    long_url: str
    created_at: datetime


class URLLookupResponse(BaseModel):
    short_code: int
    long_url: str
    created_at: datetime

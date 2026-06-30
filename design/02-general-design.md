# High-Level Architecture

> This diagram shows the **target production design**

```mermaid
---
config:
  layout: elk
  theme: neutral
---
flowchart TB

    subgraph Client
        User["Browser / Mobile App<br/>(React / Next.js)"]
    end

    subgraph Edge
        CDN["CDN<br/>(Cloudflare / AWS CloudFront)"]
        LB["Load balancer<br/>(Nginx / HAProxy)"]
    end

    subgraph WritePath["Write Path"]
        APIGW["API gateway<br/>(Kong / Express / Fastify)"]
    end

    subgraph ReadPath["Read Path"]
        Redirect["API gateway<br/>(Kong / Express / Fastify)"]
    end

    subgraph AuthSvc["Auth Service"]
        Auth["Auth handler<br/>(JWT / OAuth2)"]
        subgraph AuthDB["Owned Storage"]
            UserDB[("User DB<br/>(PostgreSQL)")]
        end
    end

    subgraph ShortenerSvc["Shortener Service"]
        Shortener["Shortener handler<br/>(Node.js / Go)"]
        subgraph ShortenerDB["Owned Storage"]
            Redis["Cache<br/>(Redis / Memcached)"]
            Primary[("Primary DB<br/>(PostgreSQL / MySQL)")]
            Replica[("Replica DB<br/>(PostgreSQL / MySQL)")]
        end
    end

    subgraph Async
        Queue["Queue<br/>(Kafka / RabbitMQ / SQS)"]
        Analytics["Analytics service<br/>(ClickHouse / Elasticsearch)"]
    end

    User --> APIGW
    APIGW --> Auth
    APIGW --> Shortener

    Auth --> UserDB

    Shortener --> Redis
    Shortener --> Primary
    Primary --> Replica
    Redis -. Cache Miss .-> Replica

    User --> CDN
    CDN --> LB
    LB --> Redirect

    Redirect --> Shortener

    Redirect --> Queue
    Queue --> Analytics
```

---

# Container Design

> Shows the **running containers**, which communicate only over the internal Docker bridge network, and what is exposed to the outside world.

```mermaid
---
config:
  layout: elk
  theme: neutral
---
flowchart TB

    subgraph Outside["Outside World"]
        ExternalClient["curl / Browser / pytest"]
    end

    subgraph Exposed["Exposed to Host"]
        GW["gateway<br/>(FastAPI + Uvicorn)<br/>port 8000"]
    end

    subgraph Internal["Docker Internal Network - not reachable from host"]

        subgraph ShortenerCtr["shortener (FastAPI + Uvicorn, port 8001)"]
            direction TB
            WriteH["POST /shorten"]
            ReadH["GET /urls/:id<br/>GET /r/:id"]
        end

        subgraph AuthCtr["auth (FastAPI + Uvicorn, port 8002)"]
            direction TB
            LoginH["POST /auth/login"]
            RefreshH["POST /auth/refresh"]
            LogoutH["POST /auth/logout"]
        end

        subgraph RedisCtr["shortener-redis (Redis 7, port 6379)"]
            Cache["key: url:{id}<br/>TTL: 24h"]
        end

        subgraph DBCtr["db (PostgreSQL 16, port 5432)"]
            PG[("table: urls")]
        end

        subgraph AuthRedisCtr["auth-redis (Redis 7, port 6379)"]
            TokenStore["key: refresh_token:{token}<br/>value: user_id<br/>TTL: 30d"]
        end

        subgraph AuthDBCtr["auth-db (PostgreSQL 16, port 5432)"]
            UserPG[("table: users")]
        end

    end

    ExternalClient -->|"port 8000 - only exposed port"| GW
    GW -->|"httpx - internal network only"| ShortenerCtr
    GW -->|"httpx - internal network only"| AuthCtr
    WriteH -->|"INSERT ON CONFLICT"| PG
    ReadH -->|"GET url:{id}"| Cache
    Cache -.->|"Cache MISS"| PG
    PG -.->|"Cache WARM"| Cache
    LoginH -->|"SELECT / INSERT"| UserPG
    LoginH -->|"SET refresh_token:{token}"| TokenStore
    RefreshH -->|"GET refresh_token:{token}"| TokenStore
    LogoutH -->|"DEL refresh_token:{token}"| TokenStore
```

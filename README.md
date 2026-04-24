# Helpdesk — Sistema de Tickets

Plataforma de soporte técnico basada en microservicios. Permite gestionar tickets, categorías, prioridades, SLA y usuarios desde una interfaz web moderna.

## Stack

| Capa | Tecnología |
|------|-----------|
| Frontend | React 19 + Vite, shadcn/ui, Tailwind CSS v4, TanStack Query, Zustand |
| API Gateway | NestJS (HTTP REST + Swagger) |
| Microservicios | NestJS (NATS JetStream) |
| Base de datos | PostgreSQL 16 + Prisma ORM |
| Mensajería | NATS JetStream |
| Contenedores | Docker + Docker Compose |

## Arquitectura

```
Browser (port 5173)
    │
    ▼
frontend-app  ──HTTP──▶  api-gateway (port 3000)
                               │
                    ┌──────────┼──────────┐──────────────┐
                    │ NATS JetStream      │              │
                    ▼                     ▼              ▼
             auth-service          tickets-service    mant-service
                    │                     │              │
             db-auth (5432)      db-tickets (5433)    db-mant (5434)
```

El api-gateway es el único servicio público. Todos los microservicios se comunican exclusivamente por NATS — nunca reciben conexiones HTTP directas.

## Funcionalidades

- **Autenticación**: JWT con refresh tokens (HttpOnly cookies), sesiones persistidas en BD con hash bcrypt
- **Roles y permisos**: Control de acceso granular (admin / técnico / usuario)
- **Tickets**: Creación, asignación, comentarios, acciones, estados, cierre y resolución
- **Configuración**: Categorías, prioridades, SLA, horarios hábiles, tipos de ticket
- **Empresas y departamentos**: Estructura organizacional multi-tenant

## Requisitos

- Docker y Docker Compose
- Node.js 20+ y pnpm (solo para desarrollo local fuera de Docker)

## Instalación

### 1. Clonar el repositorio

```bash
git clone <repo-url>
cd app-launcher
```

### 2. Crear el archivo de entorno

Copia el ejemplo y rellena los valores:

```bash
cp .env.example .env.development
```

Variables requeridas:

```env
# PostgreSQL
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_password
POSTGRES_DB_AUTH=db_auth
POSTGRES_DB_TICKETS=db_tickets

# Usuarios de aplicación (auth-service)
APP_USER_AUTH=auth_user
APP_USER_AUTH_PASSWORD=auth_password

# Usuarios de aplicación (tickets-service)
APP_USER_TICKETS=tickets_user
APP_USER_TICKETS_PASSWORD=tickets_password

# Replicación
REPLICATION_USER=repl_user
REPLICATION_PASSWORD=repl_password

# NATS
NATS_SERVERS=nats://nats-server:4222

# API Gateway
API_GATEWAY_PORT=3000
APP_VERSION=1.0.0

# JWT
JWT_SECRET=your_jwt_secret
JWT_REFRESH_SECRET=your_refresh_secret
```

### 3. Levantar el stack

```bash
docker compose up --build (DEV)
docker compose -f compose.prod.yml up --build (PROD)
```

El stack inicia en este orden: bases de datos → NATS → microservicios → api-gateway.

### 4. Frontend (desarrollo local)

```bash
cd frontend-app
pnpm install
pnpm run dev   # http://localhost:5173
```

## Desarrollo

### Comandos útiles

```bash
# Levantar stack completo con hot-reload
docker compose up

# Solo backend (sin frontend)
docker compose up api-gateway auth-service tickets-service mant-service

# Ver logs de un servicio
docker compose logs -f tickets-service

# Ejecutar migraciones manualmente
cd auth-service && npx prisma migrate dev --name <nombre>
cd tickets-service && npx prisma migrate dev --name <nombre>
```

### Estructura del monorepo

```
app-launcher/
├── api-gateway/        # HTTP Gateway (NestJS)
├── auth-service/       # Auth, usuarios, roles (NestJS NATS)
├── tickets-service/    # Tickets, SLA, categorías (NestJS NATS)
├── tickets-service/    # Mant, Inventarios (NestJS NATS)
├── frontend-app/       # SPA (React + Vite)
├── scripts/            # init.sh para PostgreSQL
├── compose.yml         # Stack de desarrollo
└── compose.prod.yml    # Stack de producción
```

### Frontend — estructura de features

```
src/features/
├── auth/           # Login, store Zustand, guards de ruta
├── tickets/        # Tickets (listado, detalle, creación)
├── config/         # Configuración del sistema (admin)
└── common/         # Componentes reutilizables (DataTable, etc.)
```

## API

La documentación Swagger está disponible en `http://localhost:3000/api/docs` cuando el stack está corriendo.

## Producción

```bash
docker compose -f compose.prod.yml up -d
```

## Licencia

MIT

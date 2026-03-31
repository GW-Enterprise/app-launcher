# Plan de Implementación — Helpdesk Ticketing System

> **Fecha:** 2026-03-27
> **Despliegue objetivo:** Local (Docker Compose en red privada)
> **Estado general:** ~70% completado

---

## Estado actual

### ✅ Implementado y funcional

| Área | Detalle |
|------|---------|
| Infraestructura | NestJS microservicios + NATS JetStream + Docker Compose |
| Auth | JWT + refresh token HttpOnly, bcrypt, guards, roles, permisos |
| Tickets (core) | CRUD completo, historial, asignación, resolución, cierre, pausa/reanudación |
| Comentarios | Creación, edición, internos/externos |
| SLA | Cálculo de deadlines, business hours, holidays, pausa/reanudación, breach detection |
| Categorías / subcategorías | CRUD completo |
| Prioridades / tipos / estados | CRUD completo |
| Métricas diarias | Modelos definidos (DailyGlobalMetrics, DailyTechnicianMetrics, DailySegmentMetrics) |
| WebSockets | Actualización en tiempo real por empresa (ticket:created, ticket:updated) |
| Frontend base | React + shadcn/ui + Tailwind v4 + TanStack Query + Zustand |
| Rutas protegidas | Guard de auth + roles en frontend |
| Detalle de ticket | SLA banner, metadata, acciones, comentarios, historial |
| Seed de datos | Permisos, roles, usuarios, statuses, prioridades, tipos, SLA, categorías |

---

## Fases pendientes

---

### 🔴 Fase 1 — Seguridad (BLOQUEA PRODUCCIÓN)

**Problema:** Los endpoints de tickets y configuración en el api-gateway son públicos.
Solo `status.controller.ts`, `auth` y `companies` tienen `@Auth()`.

#### Tareas

- [x] `api-gateway/src/tickets/tickets/tickets.controller.ts`
  - `GET /tickets` → `@Auth(ValidRoles.admin, ValidRoles.supervisor)`
  - `GET /tickets/user/:id` → `@Auth()` (cualquier usuario autenticado)
  - `GET /tickets/:id` → `@Auth()`
  - `POST /tickets` → `@Auth()`
  - `PATCH /tickets/:id` → `@Auth()`
  - `POST /tickets/:id/assign` → `@Auth(ValidRoles.admin, ValidRoles.supervisor)`
  - `POST /tickets/:id/resolve` → `@Auth(ValidRoles.admin, ValidRoles.supervisor)`
  - `POST /tickets/:id/close` → `@Auth(ValidRoles.admin, ValidRoles.supervisor)`
  - `POST /tickets/:id/pause` → `@Auth(ValidRoles.admin, ValidRoles.supervisor)`
  - `POST /tickets/:id/resume` → `@Auth(ValidRoles.admin, ValidRoles.supervisor)`

- [x] `api-gateway/src/tickets/categories/categories.controller.ts` → `@Auth()`
- [x] `api-gateway/src/tickets/subcategories/sub-categories.controller.ts` → `@Auth()`
- [x] `api-gateway/src/tickets/priorities/priorities.controller.ts` → `@Auth()`
- [x] `api-gateway/src/tickets/types/types.controller.ts` → `@Auth()`
- [x] `api-gateway/src/tickets/sla/sla.controller.ts` → `@Auth(ValidRoles.admin)`
- [x] `api-gateway/src/tickets/business-hours/businessHours.controller.ts` → `@Auth(ValidRoles.admin)`
- [x] `api-gateway/src/tickets/holidays/holidays.controller.ts` → `@Auth(ValidRoles.admin)`
- [x] `api-gateway/src/tickets/technicians/technicians.controller.ts` → `@Auth()`
- [x] `api-gateway/src/tickets/status/status.controller.ts` → GET endpoints `@Auth()`

**Decorador disponible:** `api-gateway/src/auth/decorators/auth.decorator.ts`

---

### 🟠 Fase 2 — Correcciones rápidas

#### 2a. Typo en message patterns de ticket-actions

**Archivo:** `tickets-service/src/tickets-actions/ticket-actions.controller.ts`

Los handlers tienen un espacio al final que los rompe silenciosamente:

```typescript
// ❌ Actual (no coincide con el api-gateway)
{ cmd: 'ticket.actions.create ' }
{ cmd: 'ticket.actions.update ' }
{ cmd: 'ticket.actions.delete ' }

// ✅ Correcto
{ cmd: 'ticket.actions.create' }
{ cmd: 'ticket.actions.update' }
{ cmd: 'ticket.actions.delete' }
```

- [x] Corregir los 3 message patterns en `ticket-actions.controller.ts`

#### 2b. CORS desde variable de entorno

**Archivo:** `api-gateway/src/main.ts`

```typescript
// ❌ Actual (hardcodeado)
origin: 'http://localhost:5173'

// ✅ Correcto
origin: process.env.ALLOWED_ORIGINS?.split(',') ?? 'http://localhost:5173'
```

- [x] Actualizar `main.ts`
- [x] Agregar `ALLOWED_ORIGINS=http://localhost:5173` a `.env.example`

---

### 🟠 Fase 3 — Rating de satisfacción

El schema ya tiene los campos: `satisfaction_rating`, `satisfaction_comment`, `rated_at`.

#### Backend

- [ ] Agregar handler `ticket.rate` en `tickets-service/src/tickets/tickets.controller.ts`
  - Solo permitido si el ticket está en status final (resolved/closed)
  - Solo el usuario que creó el ticket puede calificar
  - Campos a actualizar: `satisfaction_rating` (1–5), `satisfaction_comment`, `rated_at`
- [ ] Agregar endpoint `POST /tickets/:id/rating` en `api-gateway/src/tickets/tickets/tickets.controller.ts`
  - Guard: `@Auth()` (usuario autenticado)

#### Frontend

- [ ] Componente de estrellas interactivo (`RatingCard.tsx`) en `TicketDetailPage.tsx`
  - Visible solo cuando el ticket está en status final
  - Visible solo para el usuario que creó el ticket
  - Si ya tiene rating, mostrar como solo lectura
- [ ] `useRateTicketMutation.ts` en `frontend-app/src/features/tickets/hooks/mutations/`

---

### 🟡 Fase 4 — Notificaciones por email

Sin notificaciones, el usuario no sabe que su ticket fue atendido.

#### Arquitectura

Nuevo microservicio `notification-service` conectado por NATS (igual que los demás).

```
tickets-service  →  NATS (emit)  →  notification-service  →  Email (SMTP)
```

#### Eventos a emitir desde tickets-service

| Evento NATS | Cuándo | Destinatario |
|-------------|--------|--------------|
| `notification.ticket.created` | Al crear ticket | Admin/supervisor |
| `notification.ticket.assigned` | Al asignar técnico | Técnico asignado |
| `notification.ticket.resolved` | Al resolver | Usuario que creó |
| `notification.ticket.closed` | Al cerrar | Usuario que creó |
| `notification.ticket.comment` | Nuevo comentario externo | Usuario/técnico según rol |
| `notification.sla.breach` | SLA roto | Admin/supervisor |

#### Tareas

**notification-service (nuevo)**
- [ ] Scaffold NestJS microservicio
- [ ] Conectar a NATS con `@EventPattern`
- [ ] Integrar Nodemailer con configuración SMTP por env vars
- [ ] Templates HTML para cada tipo de notificación
- [ ] Agregar al `compose.yml`

**tickets-service**
- [ ] Inyectar `ClientProxy` NATS en `TicketsService`
- [ ] Emitir `notification.*` en: `createTicket`, `assignTicket`, `resolveTicket`, `closeTicket`, `createComment`
- [ ] Emitir `notification.sla.breach` en `SlaMonitorService` al detectar breach

**Variables de entorno requeridas**
```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=helpdesk@empresa.com
SMTP_PASS=app_password
SMTP_FROM="Helpdesk <helpdesk@empresa.com>"
```

---

### 🟡 Fase 5 — Adjuntos

El schema `TicketsAttachments` está definido pero no hay implementación.

#### Backend

- [ ] Configurar `multer` en `api-gateway` para `multipart/form-data`
- [ ] Endpoint `POST /tickets/:id/attachments` (upload)
- [ ] Endpoint `GET /tickets/:id/attachments/:filename` (descarga/preview)
- [ ] Servir archivos estáticos con `ServeStaticModule` o middleware
- [ ] Handler `ticket.attachments.upload` en `tickets-service`
- [ ] Volumen Docker para persistir archivos: `./uploads:/app/uploads`

#### Frontend

- [ ] Componente `AttachmentUploader.tsx` con drag & drop en `TicketDetailPage`
- [ ] Lista de adjuntos con nombre, tamaño y botón de descarga
- [ ] `useUploadAttachmentMutation.ts`

---

### 🟡 Fase 6 — Dashboard y Reportes

Los modelos de métricas existen pero no hay UI.

#### Tareas

- [ ] Página `/dashboard` con:
  - Tickets abiertos / resueltos hoy
  - Tickets por prioridad (gráfica de barras)
  - Tickets por técnico (tabla)
  - SLA compliance rate
- [ ] Endpoint `GET /metrics/daily` en api-gateway
- [ ] Handler en tickets-service que lea `DailyGlobalMetrics`
- [ ] Librerías sugeridas: `recharts` o `@nivo/bar` (ya en el ecosistema React)

---

### 🟢 Fase 7 — Acciones bulk

- [ ] Checkbox por fila en `TicketPage.tsx`
- [ ] Toolbar contextual al seleccionar: "Asignar a...", "Cambiar prioridad", "Cerrar"
- [ ] Endpoint `PATCH /tickets/bulk` en api-gateway
- [ ] Handler `tickets.bulk.update` en tickets-service

---

### 🟢 Fase 8 — Auto-escalamiento

`SlaMonitorService` ya corre cada 5 minutos. Solo extenderlo:

- [ ] Al detectar `sla_is_breached = true`: emitir `notification.sla.breach`
- [ ] Opcional: si lleva más de N horas sin respuesta → reasignar al supervisor

---

### 🟢 Fase 9 — HTTPS local

Solo necesario si se accede desde otros dispositivos en la red.

- [ ] Agregar nginx como reverse proxy en `compose.prod.yml`
- [ ] Generar certificado auto-firmado con `mkcert`
- [ ] Configurar `nginx.conf` con `ssl_certificate` y proxy_pass a api-gateway y frontend

---

## Orden de implementación recomendado

| # | Fase | Esfuerzo estimado | Impacto |
|---|------|-------------------|---------|
| 1 | Guards de seguridad | Bajo (decoradores) | 🔴 Crítico |
| 2 | Typo message patterns + CORS env | Muy bajo | 🟠 Alto |
| 3 | Rating de satisfacción | Bajo | 🟠 Alto |
| 4 | Notificaciones por email | Alto (nuevo servicio) | 🟠 Alto |
| 5 | Adjuntos | Medio | 🟡 Medio |
| 6 | Dashboard y reportes | Medio | 🟡 Medio |
| 7 | Bulk actions | Bajo | 🟢 Bajo |
| 8 | Auto-escalamiento | Bajo | 🟢 Bajo |
| 9 | HTTPS local | Bajo | 🟢 Opcional |

---

## Archivos clave por fase

| Fase | Archivos principales |
|------|---------------------|
| 1 - Guards | `api-gateway/src/tickets/**/**.controller.ts` |
| 2a - Typos | `tickets-service/src/tickets-actions/ticket-actions.controller.ts` |
| 2b - CORS | `api-gateway/src/main.ts`, `.env.example` |
| 3 - Rating | `tickets-service/src/tickets/tickets.{controller,service}.ts`, `TicketDetailPage.tsx` |
| 4 - Notificaciones | `notification-service/` (nuevo), `tickets-service/src/tickets/tickets.service.ts`, `sla-monitor.service.ts` |
| 5 - Adjuntos | `api-gateway/src/tickets/attachments/` (nuevo), `TicketDetailPage.tsx` |
| 6 - Dashboard | `api-gateway/src/metrics/` (nuevo), `frontend-app/src/features/dashboard/` (nuevo) |
| 7 - Bulk | `api-gateway/src/tickets/tickets.controller.ts`, `TicketPage.tsx` |
| 8 - Escalamiento | `tickets-service/src/sla/sla-monitor.service.ts` |
| 9 - HTTPS | `compose.prod.yml`, `nginx.conf` (nuevo) |

---

## Lo que NO cambiar

- **Arquitectura NATS + microservicios**: bien diseñada para el alcance del proyecto
- **Lógica SLA**: correcta y completa
- **Sistema de historial/audit**: completo, no tocar
- **Modelos de métricas**: ya capturan lo necesario
- **Sistema de permisos granular**: sólido, solo falta aplicarlo en los guards

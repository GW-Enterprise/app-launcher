# Plan: Mejoras al Sistema de Tickets

## Contexto

El sistema tiene una base sólida: lógica SLA bien estructurada, historial de cambios, pausas, métricas diarias, relaciones entre tickets.

> **Despliegue objetivo: local** (Docker Compose en red privada). No se requiere cloud ni CDN.

---

## Estado de implementación

### ✅ Completado

- **Fase 2a — Comentarios**: `useCreateCommentMutation.ts` y `CommentComposer.tsx` implementados
- **Fase 2b — Botones de acción**: `TicketActionBar.tsx` con resolver/cerrar/pausar/asignar implementado

### ❌ Pendiente

---

## Priorización

### 🔴 Fase 1 — Seguridad (bloquea producción)

**Aplicar guards a todos los endpoints del api-gateway**

Estado actual: solo `status.controller.ts` y los controllers de `auth` y `companies` usan `@Auth()`. Los endpoints de tickets, categorías, SLA, etc. son públicos.

**Cambios:**
- `tickets.controller.ts` (api-gateway): aplicar `@UseGuards(AuthGuard)` a todos los endpoints. Los admin-only (assign, close, listar todos) también `@Auth(ValidRoles.admin)`.
- Controllers de config: categories, subcategories, priorities, types, sla, business-hours, holidays.
- Decorador disponible: `api-gateway/src/auth/decorators/auth.decorator.ts`

---

### 🟠 Fase 2c — Satisfacción del usuario

El schema ya tiene `satisfaction_rating`, `satisfaction_comment`, `rated_at`. Solo falta:
- Endpoint en api-gateway: `POST /tickets/:id/rating`
- Handler en tickets-service: actualiza los 3 campos, solo si ticket está en status final
- UI: card con estrellas (1-5) visible al usuario cuando el ticket está resuelto

---

### 🟡 Fase 3 — Notificaciones

Sin notificaciones, el usuario no sabe que su ticket fue atendido/resuelto.

**Arquitectura: nuevo microservicio `notification-service`**
- Se comunica por NATS igual que los demás
- El `tickets-service` emite eventos NATS (fire-and-forget):
  - `notification.ticket.created` → al usuario que creó el ticket
  - `notification.ticket.assigned` → al técnico asignado
  - `notification.ticket.resolved` → al usuario
  - `notification.ticket.comment` → al usuario/técnico según tipo
  - `notification.sla.breach` → al admin/supervisor
- El `notification-service` consume los eventos y envía email via **Nodemailer** (SMTP local o Gmail)
- Templates HTML sencillos

**Cambios en tickets-service:**
- Inyectar `ClientProxy` NATS
- Emitir eventos en: createTicket, resolveTicket, assignTicket, closeTicket, y comentarios

---

### 🟢 Fase 4 — UX y features incompletas

#### 4a. Adjuntos (attachments)
El schema tiene `TicketAttachment` con `url`, `filename`, `mime_type`. Solo falta:
- Storage: **disco local con multer** (sin S3, despliegue local)
- Endpoint: `POST /tickets/:id/attachments` (multipart/form-data)
- Servir archivos estáticos desde api-gateway
- UI: zona de drag & drop en el detalle, lista de archivos descargables

#### 4b. Acciones bulk en la lista
- Checkbox por fila en `TicketPage.tsx`
- Toolbar al seleccionar: "Asignar a...", "Cambiar prioridad", "Cerrar seleccionados"
- Endpoint: `PATCH /tickets/bulk` en api-gateway

#### 4c. Escalamiento automático
El `SlaMonitorService` ya corre cada 5 min. Extenderlo para:
- Cuando `sla_is_breached = true` → emitir `notification.sla.breach`
- Opcional: auto-reasignar a supervisor si lleva X tiempo sin respuesta

#### 4d. CORS en producción
Actualmente hardcodeado a `localhost:5173`. Mover a variable de entorno `ALLOWED_ORIGINS`.

#### 4e. HTTPS local
Configurar nginx como reverse proxy con certificado auto-firmado para la red local.
Opcional si solo se accede desde localhost.

---

## Archivos críticos por fase

| Fase | Archivos a modificar |
|------|---------------------|
| 1 - Guards | `api-gateway/src/tickets/tickets.controller.ts`, controllers de config en api-gateway |
| 2c - Satisfacción | `tickets.service.ts`, `tickets.controller.ts` (tickets-service), `TicketDetailPage.tsx` |
| 3 - Notificaciones | `tickets.service.ts`, nuevo `notification-service/` completo |
| 4a - Adjuntos | api-gateway (multer), `tickets.service.ts`, `TicketDetailPage.tsx` |
| 4b - Bulk | `TicketPage.tsx`, api-gateway controller |
| 4c - Escalamiento | `sla-monitor.service.ts` |
| 4d - CORS | `api-gateway/src/main.ts`, `.env` |
| 4e - HTTPS | `compose.prod.yml`, nuevo `nginx.conf` |

---

## Orden recomendado para implementar

1. **Guards** — sin esto, los endpoints son públicos
2. **CORS desde env** — un cambio de 2 líneas, evita problemas al acceder desde otro host local
3. **Satisfacción** — el schema ya lo soporta todo
4. **Notificaciones** — valor alto para el usuario final
5. **Adjuntos** — storage local con multer, sin dependencias externas
6. **Bulk actions** — comodidad, no bloqueante
7. **Escalamiento automático** — extensión del cron existente
8. **HTTPS local** — solo si se accede desde otros dispositivos en la red

---

## Lo que NO cambiaría

- La arquitectura NATS + microservicios: está bien para este proyecto
- La lógica SLA actual: ya está corregida y funciona
- El sistema de historial/audit: es completo
- Los modelos de métricas: ya capturan lo necesario, solo falta UI de reportes

# Plan: Mejoras al Sistema de Tickets

## Contexto

El sistema tiene una base sólida: lógica SLA bien estructurada, historial de cambios, pausas, métricas diarias, relaciones entre tickets. Sin embargo, hay brechas que lo hacen incompleto como helpdesk real:
- **Seguridad**: casi ningún endpoint tiene guards aplicados
- **Flujos incompletos**: comentarios, resolve/close/pause no tienen botones directos en el frontend
- **Sin notificaciones**: el sistema no avisa a nadie de nada
- **UX**: el agente no puede operar cómodamente desde el detalle del ticket

---

## Priorización (qué hacer primero)

### 🔴 Fase 1 — Seguridad (bloquea todo lo demás)
**Aplicar guards a todos los endpoints del api-gateway**

Estado actual: solo `status.controller.ts` usa `@Auth()`. Los 13 endpoints de tickets, categorías, SLA, etc. son públicos.

**Cambios:**
- `tickets.controller.ts` (api-gateway): aplicar `@UseGuards(AuthGuard)` a todos los endpoints. Los que son solo-admin (assign, close, listar todos) también aplicar `@Auth(ValidRoles.admin)`.
- Igual para los controllers de config: categories, subcategories, priorities, types, sla, business-hours, holidays.
- Archivo crítico: `api-gateway/src/tickets/tickets.controller.ts`
- Decorador disponible: `api-gateway/src/auth/decorators/auth.decorator.ts`

---

### 🟠 Fase 2 — Flujos de operación en el ticket (los más usados a diario)

#### 2a. Crear comentarios desde el frontend
El API ya existe (`POST /tickets/:id/comments`) pero no hay UI para crearlo. El frontend solo muestra comentarios.

**Cambios:**
- Agregar `useCreateComment` mutation en `hooks/mutations/`
- Agregar un input/textarea con botón "Enviar" debajo de la lista de comentarios en `TicketDetailPage.tsx`
- Soporte para "nota interna" (checkbox) vs comentario público

#### 2b. Botones de acción directa en el ticket
Actualmente para resolver/cerrar/pausar un ticket hay que ir a modo edición, cambiar el status en el select, y guardar. Esto es torpe.

**Cambios en `TicketDetailPage.tsx`:**
- Botón **"Resolver"** → llama `POST /tickets/:id/resolve` (solo visible si status no es final)
- Botón **"Cerrar"** → llama `POST /tickets/:id/close` (solo si resuelto)
- Botón **"Pausar / Reanudar"** → llama `POST /tickets/:id/pause` o `/resume` según estado actual
- Botón **"Asignarme"** → llama `POST /tickets/:id/assign` con el id del técnico logueado
- Estos botones van en la barra superior del detalle, visibles según el rol y estado del ticket
- Agregar mutations para cada acción en `useTicketsMutation.ts` o en archivos separados

#### 2c. Satisfacción del usuario
El schema ya tiene `satisfaction_rating`, `satisfaction_comment`, `rated_at`. Solo falta:
- Endpoint en api-gateway: `POST /tickets/:id/rating`
- Handler en tickets-service: actualiza los 3 campos, solo si ticket está en status final
- UI: card simple con estrellas (1-5) visible al usuario cuando el ticket está resuelto

---

### 🟡 Fase 3 — Notificaciones (la más impactante para el usuario final)

Sin notificaciones, el usuario no sabe que su ticket fue atendido/resuelto. El sistema de permisos ya tiene `notifications:send`, `notifications:configure`, etc., pero no hay infraestructura.

**Arquitectura recomendada: nuevo microservicio `notification-service`**
- Se comunica por NATS igual que los demás
- El `tickets-service` emite eventos NATS (no espera respuesta):
  - `notification.ticket.created` → al usuario que creó el ticket
  - `notification.ticket.assigned` → al técnico asignado
  - `notification.ticket.resolved` → al usuario
  - `notification.ticket.comment` → al usuario/técnico según el tipo de comentario
  - `notification.sla.breach` → al admin/supervisor
- El `notification-service` consume los eventos y envía email via Nodemailer/Resend
- Templates de email en HTML sencillo

**Cambios en tickets-service:**
- Inyectar `ClientProxy` NATS en `TicketsService`
- Emitir eventos `this.natsClient.emit(...)` en: createTicket, resolveTicket, assignTicket, closeTicket, y en la lógica de comentarios

**Datos mínimos para notificar:**
- Email del usuario (`user.email` — ya está en el ticket al incluir la relación)
- Email del técnico asignado

---

### 🟢 Fase 4 — Mejoras de UX y completar features existentes

#### 4a. Adjuntos (attachments)
El schema tiene `TicketAttachment` con `url`, `filename`, `mime_type`. Solo falta:
- Storage: S3/Cloudflare R2 o simplemente disco local con multer en el api-gateway
- Endpoint: `POST /tickets/:id/attachments` (multipart/form-data)
- UI: zona de drag & drop en el detalle del ticket, lista de archivos descargables

#### 4b. Acciones bulk en la lista
- Checkbox por fila en `TicketPage.tsx`
- Toolbar que aparece cuando hay seleccionados: "Asignar a...", "Cambiar prioridad", "Cerrar seleccionados"
- Requiere endpoint `PATCH /tickets/bulk` en api-gateway

#### 4c. Escalamiento automático
El `SlaMonitorService` ya corre cada 5 min y detecta breaches. Extenderlo para:
- Cuando `sla_is_breached = true` → emitir `notification.sla.breach` con datos del ticket
- Opcionalmente: auto-reasignar a supervisor si lleva X tiempo sin respuesta

---

## Archivos críticos por fase

| Fase | Archivos a modificar |
|------|---------------------|
| 1 - Guards | `api-gateway/src/tickets/tickets.controller.ts`, controllers de config en api-gateway |
| 2a - Comentarios | `TicketDetailPage.tsx`, nuevo `useCreateCommentMutation.ts` |
| 2b - Acciones | `TicketDetailPage.tsx`, `useTicketsMutation.ts`, `actions/actions.ts` |
| 2c - Satisfacción | `tickets.service.ts`, `tickets.controller.ts` (tickets-service), `TicketDetailPage.tsx` |
| 3 - Notificaciones | `tickets.service.ts`, nuevo `notification-service/` completo |
| 4a - Adjuntos | api-gateway (multer), `tickets.service.ts`, `TicketDetailPage.tsx` |
| 4b - Bulk | `TicketPage.tsx`, api-gateway controller |
| 4c - Escalamiento | `sla-monitor.service.ts` |

---

## Orden recomendado para implementar

1. **Guards** — sin esto, lo demás no debería estar en producción
2. **Botones de acción** — impacto inmediato en el flujo de trabajo del agente
3. **Crear comentarios** — comunicación básica helpdesk
4. **Notificaciones** — valor alto para el usuario final
5. **Satisfacción** — fácil, el schema ya lo soporta todo
6. **Adjuntos** — depende de la infraestructura de storage disponible
7. **Bulk actions** — comodidad, no bloqueante
8. **Escalamiento automático** — extensión natural del cron existente

---

## Lo que NO cambiaría

- La arquitectura NATS + microservicios: está bien para este proyecto
- La lógica SLA actual: ya está corregida y funciona
- El sistema de historial/audit: es completo
- Los modelos de métricas: ya capturan lo necesario, solo falta UI de reportes

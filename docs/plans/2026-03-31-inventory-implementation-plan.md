# Inventory Module — Implementation Plan

**Date:** 2026-03-31
**Design doc:** `docs/plans/2026-03-31-inventory-design.md`

---

## Phase 1 — Backend: inventory-service scaffold

### Step 1.1 — Scaffold NestJS microservice
- Crear directorio `inventory-service/` copiando estructura de `tickets-service`
- Configurar `package.json`, `tsconfig.json`, `nest-cli.json`
- Instalar dependencias: `@nestjs/microservices`, `nats`, `prisma`, `@prisma/client`, `joi`
- Crear `src/config/envs.ts` con validación Joi (`DATABASE_URL`, `NATS_SERVERS`)
- Crear `src/main.ts` como microservicio NATS

### Step 1.2 — Prisma schema
Crear `prisma/schema.prisma` con modelos:
- `UnitOfMeasure`
- `ItemCategory`
- `Item`
- `Location`
- `MovementOrder`
- `MovementOrderLine`

Ejecutar `npx prisma migrate dev --name init`

### Step 1.3 — Docker
- Agregar `inventory-service` y `db-inventory` a `docker-compose.yml`
- Agregar `DB_INVENTORY_URL` y variables al `.env.example`

---

## Phase 2 — Backend: catálogos

### Step 2.1 — UnitsOfMeasure module
- `units-of-measure.controller.ts` con patterns: `find_all`, `create`, `update`, `delete`
- `units-of-measure.service.ts` con CRUD básico
- DTOs: `CreateUnitDto`, `UpdateUnitDto`

### Step 2.2 — ItemCategories module
- Igual que UnitsOfMeasure
- Patterns: `inventory.item_categories.*`

### Step 2.3 — Locations module
- CRUD con campo `type` enum (`machine | area | warehouse`)
- Patterns: `inventory.locations.*`

### Step 2.4 — Items module
- CRUD con relaciones a `UnitOfMeasure` e `ItemCategory`
- Incluir `current_price`, `current_stock`, `min_stock`
- Endpoint adicional: `inventory.items.low_stock` (stock <= min_stock)
- Patterns: `inventory.items.*`

---

## Phase 3 — Backend: movimientos (núcleo)

### Step 3.1 — Movements module
Crear `movements.service.ts` con método `createMovement`:

```typescript
async createMovement(dto: CreateMovementDto) {
  return this.prisma.$transaction(async (tx) => {
    // 1. Validar ítems activos
    // 2. Validar stock para salidas
    // 3. Generar order_number (SAL-0001 / ENT-0001)
    // 4. Crear MovementOrder
    // 5. Crear MovementOrderLines con unit_price capturado
    // 6. Actualizar current_stock en cada Item
  });
}
```

### Step 3.2 — DTOs de movimiento
```typescript
CreateMovementDto {
  movement_type: 'entry' | 'exit'
  location_id: number
  notes?: string
  lines: CreateMovementLineDto[]
}

CreateMovementLineDto {
  item_id: number
  quantity: number
  // unit_price se captura del item, no viene del cliente
}
```

### Step 3.3 — Queries y reportes
- `findAll` con filtros: `movement_type`, `location_id`, `date_from`, `date_to`
- `findOne` con líneas incluidas
- `monthlyCosts`: agrupar salidas por mes → `SUM(total_price)`
- `byLocation`: salidas por `location_id` en período → `SUM(total_price)` por ubicación

---

## Phase 4 — api-gateway: endpoints HTTP

### Step 4.1 — Inventory proxy module
Crear `api-gateway/src/inventory/` con:
- `inventory.module.ts` — conecta con NATS `inventory-service`
- `inventory-items.controller.ts`
- `inventory-locations.controller.ts`
- `inventory-movements.controller.ts`
- `inventory-catalogs.controller.ts` (units + categories)

### Step 4.2 — Rutas HTTP
```
GET    /api/inventory/items
POST   /api/inventory/items
PATCH  /api/inventory/items/:id
DELETE /api/inventory/items/:id
GET    /api/inventory/items/low-stock

GET    /api/inventory/locations
POST   /api/inventory/locations
PATCH  /api/inventory/locations/:id

GET    /api/inventory/units
POST   /api/inventory/units

GET    /api/inventory/categories
POST   /api/inventory/categories

POST   /api/inventory/movements          ← crear entrada/salida
GET    /api/inventory/movements          ← lista con filtros
GET    /api/inventory/movements/:id      ← detalle con líneas
GET    /api/inventory/reports/monthly
GET    /api/inventory/reports/by-location
```

### Step 4.3 — Guards
Aplicar `@UseGuards(AuthGuard, RolesGuard, PermissionsGuard)` según corresponda en cada endpoint.

---

## Phase 5 — Frontend: feature/inventory

### Step 5.1 — Estructura base
```
frontend-app/src/features/inventory/
  actions/
    items.actions.ts
    locations.actions.ts
    movements.actions.ts
    catalogs.actions.ts    (units + categories)
    reports.actions.ts
  hooks/
    queries/
      useItemsQuery.ts
      useLocationsQuery.ts
      useMovementsQuery.ts
      useReportsQuery.ts
    mutations/
      useItemsMutation.ts
      useLocationsMutation.ts
      useMovementsMutation.ts
  routes/
    inventory.routes.tsx
```

### Step 5.2 — Catálogos (páginas simples CRUD)
- `ItemsPage.tsx` — tabla con columnas: código, nombre, categoría, unidad, precio, stock, mínimo; modal CRUD
- `LocationsPage.tsx` — tabla con tipo (badge); modal CRUD
- `CatalogsPage.tsx` — tabs para Categorías y Unidades de Medida

### Step 5.3 — Movimientos
- `MovementsPage.tsx` — tabla con filtros (tipo, ubicación, rango de fechas)
- `MovementDetailPage.tsx` — detalle de orden con tabla de líneas y totales
- `NewMovementPage.tsx`:
  - Select tipo (Entrada / Salida)
  - Select ubicación
  - Tabla dinámica de líneas: buscar ítem → cantidad → precio y subtotal se calculan al vuelo
  - Total general al final
  - Submit → POST `/api/inventory/movements`

### Step 5.4 — Reportes
- `ReportsPage.tsx`:
  - Tab "Gasto mensual": selector de año → tabla/gráfica mes vs. total
  - Tab "Por ubicación": selector de período → tabla ubicación vs. total

### Step 5.5 — Integración de rutas
Agregar en `frontend-app/src/router.tsx` (o donde estén las rutas protegidas):
```tsx
<Route path="/inventory/*" element={<InventoryRoutes />} />
```

Agregar enlace en el menú lateral.

---

## Phase 6 — QA y cierre

- Probar flujo completo: crear ítem → registrar entrada → registrar salida → verificar stock
- Verificar rollback de transacción si falta stock
- Verificar precio congelado en línea vs. precio actual del ítem
- Probar reportes mensuales y por ubicación
- Revisar alertas de stock mínimo

---

## Orden sugerido de implementación

1. Phase 1 (scaffold + BD) → base del servicio
2. Phase 2 (catálogos) → datos maestros necesarios para movimientos
3. Phase 3 (movimientos) → núcleo de negocio
4. Phase 4 (api-gateway) → exponer HTTP
5. Phase 5 (frontend) → UI por secciones: catálogos → movimientos → reportes
6. Phase 6 (QA)

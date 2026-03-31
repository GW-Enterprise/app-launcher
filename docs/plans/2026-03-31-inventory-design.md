# Inventory Module — Design Document

**Date:** 2026-03-31
**Status:** Approved

---

## Overview

Independent maintenance inventory module implemented as a new NestJS microservice (`inventory-service`). Completely decoupled from `tickets-service`. Manages catalogs of tools/consumables, entry/exit movements, stock control, and cost reporting per location and month.

---

## Architecture

```
Browser → frontend-app (:5173)
              ↓ HTTP
          api-gateway (:3000)   ← roles/permissions guards
              ↓ NATS JetStream
          inventory-service (NestJS NATS)
              ↓
          db-inventory (PostgreSQL :5434)
```

- New Docker containers: `inventory-service` + `db-inventory` added to existing `docker-compose.yml`
- Access control delegated entirely to api-gateway guards (roles/permissions)
- NATS message patterns prefixed with `inventory.*`

---

## Database Schema

### Catalogs

**`UnitOfMeasure`**
| Field | Type | Notes |
|---|---|---|
| id | Int PK | |
| name | String | e.g. pieza, kg, litro, metro |
| abbreviation | String | e.g. pza, kg, lt, m |
| is_active | Boolean | |
| createdAt / updatedAt | DateTime | |

**`ItemCategory`**
| Field | Type | Notes |
|---|---|---|
| id | Int PK | |
| name | String unique | |
| description | String? | |
| is_active | Boolean | |
| createdAt / updatedAt | DateTime | |

**`Item`** (tools, consumables)
| Field | Type | Notes |
|---|---|---|
| id | Int PK | |
| code | String unique | e.g. INS-001 |
| name | String | |
| description | String? | |
| category_id | Int FK → ItemCategory | |
| unit_of_measure_id | Int FK → UnitOfMeasure | |
| current_price | Decimal | Current unit price |
| current_stock | Decimal | Denormalized — updated on each movement |
| min_stock | Decimal? | Alert threshold |
| is_active | Boolean | |
| createdAt / updatedAt | DateTime | |

**`Location`** (machines, areas, warehouses)
| Field | Type | Notes |
|---|---|---|
| id | Int PK | |
| name | String unique | |
| description | String? | |
| type | Enum | machine \| area \| warehouse |
| is_active | Boolean | |
| createdAt / updatedAt | DateTime | |

### Movements

**`MovementOrder`** (the event)
| Field | Type | Notes |
|---|---|---|
| id | Int PK | |
| order_number | String unique | SAL-0001 / ENT-0001 |
| movement_type | Enum | entry \| exit |
| location_id | Int FK → Location | Destination (exit) or source (entry) |
| notes | String? | |
| registered_by | String | user_id from auth context |
| createdAt | DateTime | |

**`MovementOrderLine`** (one row per item type)
| Field | Type | Notes |
|---|---|---|
| id | Int PK | |
| order_id | Int FK → MovementOrder | |
| item_id | Int FK → Item | |
| quantity | Decimal | Amount moved |
| unit_price | Decimal | **Captured at movement time** |
| total_price | Decimal | quantity × unit_price (stored) |

### Key Indexes
- `MovementOrder(movement_type, createdAt)` — monthly reports
- `MovementOrder(location_id, createdAt)` — cost by location
- `MovementOrderLine(item_id)` — item movement history
- `Item(current_stock)` — low-stock alerts

---

## Service Modules

```
inventory-service/src/
  items/              CRUD + catalog
  item-categories/    CRUD
  units-of-measure/   CRUD
  locations/          CRUD
  movements/          create entry/exit, list, reports
  prisma/
  config/
```

---

## NATS Message Patterns

```
inventory.items.find_all
inventory.items.find_one
inventory.items.create
inventory.items.update
inventory.items.delete

inventory.item_categories.find_all
inventory.item_categories.create
inventory.item_categories.update

inventory.units.find_all
inventory.units.create
inventory.units.update

inventory.locations.find_all
inventory.locations.create
inventory.locations.update
inventory.locations.delete

inventory.movements.create          ← creates order + lines + updates stock (transaction)
inventory.movements.find_all        ← filters: type, location_id, date range, item_id
inventory.movements.find_one        ← order detail with lines
inventory.movements.monthly_costs   ← report: total exit cost grouped by month
inventory.movements.by_location     ← report: exit cost by location in a period
inventory.items.low_stock           ← items where current_stock <= min_stock
```

---

## Movement Creation Logic

Executed inside a single **Prisma transaction**:

1. Validate all `item_id` values exist and are active
2. For **exits**: validate `item.current_stock >= line.quantity` for each line
3. Capture `unit_price = item.current_price` per line
4. Calculate `total_price = quantity × unit_price`
5. Insert `MovementOrder` + all `MovementOrderLine` records
6. Update `item.current_stock` (exit: `-= quantity`, entry: `+= quantity`)
7. Auto-generate `order_number` with sequence (SAL-0001 / ENT-0001)

If any step fails → full rollback.

---

## Reports

| Report | Query |
|---|---|
| Monthly spending | `SUM(line.total_price)` of exits grouped by month/year |
| Cost by location | `SUM(line.total_price)` of exits filtered by `location_id` + date range |
| Exit detail | Lines of a specific `MovementOrder` with subtotals |
| Current stock | Direct read of `item.current_stock` |
| Low stock alerts | `WHERE current_stock <= min_stock AND is_active = true` |

---

## Frontend Feature Structure

```
frontend-app/src/features/inventory/
  pages/
    ItemsPage.tsx           catalog table + CRUD modal
    CategoriesPage.tsx      item categories CRUD
    UnitsPage.tsx           units of measure CRUD
    LocationsPage.tsx       locations/machines CRUD
    MovementsPage.tsx       movement list with filters
    NewMovementPage.tsx     form: type + location + dynamic item lines
    ReportsPage.tsx         monthly costs + by location charts/tables
  components/
    MovementLinesTable.tsx  dynamic rows for movement creation
    StockBadge.tsx          visual indicator (ok / low / out)
  hooks/
    queries/
    mutations/
  actions/                  axios calls to api-gateway
  routes/
    inventory.routes.tsx    protected routes with role guard
```

Route prefix: `/inventory/*` added to protected routes with role-based access.

---

## Environment Variables (new)

```env
POSTGRES_DB_INVENTORY=db_inventory
DB_INVENTORY_URL=postgresql://user:pass@db-inventory:5434/db_inventory
```

---

## Docker Compose Additions

```yaml
inventory-service:
  build: ./inventory-service
  depends_on: [nats-server, db-inventory]
  environment:
    - NATS_SERVERS=nats://nats-server:4222
    - DATABASE_URL=...

db-inventory:
  image: postgres:16-alpine
  ports: ["5434:5432"]
  environment:
    POSTGRES_DB: db_inventory
```

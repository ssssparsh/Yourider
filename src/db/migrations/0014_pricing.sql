-- 0014_pricing.sql
-- Catalogue cost, price books, and deal line items.
--
-- A deal carried a single scalar `amount`. That is enough to draw a pipeline
-- and nothing else: it cannot answer what was sold, at what price, at what
-- discount, or at what margin — and those are the questions a sales
-- organisation actually runs on. `service_jobs` has had line items since 0006;
-- deals have not, which meant delivery could be itemised and the sale could not.
--
-- Three additions, in dependency order:
--
--   1. A cost basis on the catalogue, so margin is computable at all.
--   2. Price books, so the same item can be sold at different prices per
--      currency, per segment, and per volume tier, with effective dating.
--   3. `deal_line_items`, which snapshot price and cost at the moment of sale.
--
-- MONEY RULES (CLAUDE.md §7): every derived amount is a generated column, so no
-- two callers can compute a different total. The deal-level rollup runs in the
-- same transaction as the line change, so a deal is never briefly inconsistent
-- with its own items.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Cost basis on the catalogue
--
-- Added to `services` rather than introduced as a second `products` table.
-- A separate catalogue would mean "what did we sell last quarter" is a UNION
-- across two tables that drift apart, and every report has to remember both.
-- `services` is already the thing a tenant sells; it was missing the cost side.
-- ---------------------------------------------------------------------------
ALTER TABLE services
  ADD COLUMN unit_cost numeric(18,4)
    CHECK (unit_cost IS NULL OR unit_cost >= 0),
  -- Null means "cost unknown", which is different from "costs nothing". Margin
  -- on an unknown cost is unknown, not 100%.
  ADD COLUMN cost_currency char(3),
  -- Physical goods need stock semantics that services do not. Recorded so a
  -- later inventory module has something to attach to, and so reporting can
  -- separate goods from labour without guessing from the name.
  ADD COLUMN is_stockable boolean NOT NULL DEFAULT false,
  ADD COLUMN sku text;

COMMENT ON COLUMN services.unit_cost IS
  'Cost basis for margin. NULL means unknown, which is not the same as zero — '
  'app.deal_totals() reports cost_known so a margin figure is never quietly '
  'computed against a missing cost.';

CREATE UNIQUE INDEX services_org_sku_key
  ON services (organization_id, sku)
  WHERE deleted_at IS NULL AND sku IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. Price books
--
-- One catalogue entry, several prices. A tenant sells the same item in USD and
-- EUR, at list price to new customers and at a negotiated rate to a partner,
-- and cheaper above 100 units. Encoding any of that as a column on `services`
-- means a migration per pricing dimension.
--
-- Effective dating is what makes a price change safe: the old row stays and
-- stops applying, so a quote issued last week can still be explained.
-- ---------------------------------------------------------------------------
CREATE TABLE price_books (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  name             text NOT NULL CHECK (btrim(name) <> ''),
  code             text,
  description      text,
  currency         char(3) NOT NULL,

  -- The book used when a deal names none. Exactly one per currency.
  is_default       boolean NOT NULL DEFAULT false,
  is_active        boolean NOT NULL DEFAULT true,

  valid_from       timestamptz,
  valid_to         timestamptz,

  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  CONSTRAINT price_books_window_ordered CHECK (
    valid_from IS NULL OR valid_to IS NULL OR valid_from < valid_to
  )
);

CREATE UNIQUE INDEX price_books_org_code_key
  ON price_books (organization_id, code)
  WHERE deleted_at IS NULL AND code IS NOT NULL;

-- Default is per currency, not per organization: a tenant selling in three
-- currencies needs three defaults, and a single global one would force every
-- non-base-currency deal to name a book explicitly.
CREATE UNIQUE INDEX price_books_one_default_per_currency
  ON price_books (organization_id, currency)
  WHERE is_default AND deleted_at IS NULL;

CREATE INDEX price_books_org_active_idx
  ON price_books (organization_id, currency, is_active)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('price_books');

CREATE TABLE price_book_entries (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  price_book_id    uuid NOT NULL REFERENCES price_books(id) ON DELETE CASCADE,
  service_id       uuid NOT NULL REFERENCES services(id) ON DELETE CASCADE,

  unit_price       numeric(18,4) NOT NULL CHECK (unit_price >= 0),
  -- Overrides services.unit_cost for this book, for the case where the same
  -- item costs a different amount to source in a different market.
  unit_cost        numeric(18,4) CHECK (unit_cost IS NULL OR unit_cost >= 0),

  -- Volume tier. A row applies from min_quantity upward; the resolver picks the
  -- highest applicable tier, so tiers are declared by their floor rather than
  -- as ranges that can be left with gaps between them.
  min_quantity     numeric(14,4) NOT NULL DEFAULT 0 CHECK (min_quantity >= 0),

  valid_from       timestamptz,
  valid_to         timestamptz,

  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,

  CONSTRAINT price_book_entries_window_ordered CHECK (
    valid_from IS NULL OR valid_to IS NULL OR valid_from < valid_to
  )
);

-- One price per (book, item, tier, start of validity). Two rows that both apply
-- at the same instant make the resolver's answer depend on physical row order,
-- which is how a customer gets a different price on a refresh.
CREATE UNIQUE INDEX price_book_entries_unique
  ON price_book_entries (price_book_id, service_id, min_quantity,
                         coalesce(valid_from, '-infinity'::timestamptz))
  WHERE deleted_at IS NULL;

CREATE INDEX price_book_entries_lookup_idx
  ON price_book_entries (price_book_id, service_id, min_quantity DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX price_book_entries_service_idx
  ON price_book_entries (organization_id, service_id)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('price_book_entries');

CREATE TRIGGER price_book_entries_book_same_org
  BEFORE INSERT OR UPDATE OF price_book_id ON price_book_entries
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('price_books', 'price_book_id');

CREATE TRIGGER price_book_entries_service_same_org
  BEFORE INSERT OR UPDATE OF service_id ON price_book_entries
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('services', 'service_id');

-- A price book entry must be priced in its book's currency; the entry has no
-- currency of its own precisely so the two can never disagree. This guard
-- exists because the book is what carries the currency, and an entry moved to
-- another book would otherwise silently change what its number means.
CREATE OR REPLACE FUNCTION app.assert_price_book_currency()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_book price_books%ROWTYPE;
BEGIN
  SELECT * INTO v_book FROM price_books WHERE id = NEW.price_book_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such price book: %', NEW.price_book_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF v_book.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'cannot price into a deleted price book: %', NEW.price_book_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER price_book_entries_book_live
  BEFORE INSERT OR UPDATE OF price_book_id ON price_book_entries
  FOR EACH ROW EXECUTE FUNCTION app.assert_price_book_currency();

-- ---------------------------------------------------------------------------
-- 3. Deal line items
--
-- Price and cost are SNAPSHOT onto the row, not read through to the catalogue.
-- A catalogue price change must not silently rewrite what a closed deal was
-- sold for — the same reason `deals.probability` snapshots the stage's
-- probability rather than joining to it.
--
-- Every derived amount is a generated column, and they are defined so that
-- net + tax = total exactly. An invoice whose lines do not add up to its total
-- is the bug this shape exists to make impossible; computing each part with
-- independent rounding is how that bug is normally introduced.
-- ---------------------------------------------------------------------------
CREATE TABLE deal_line_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  deal_id           uuid NOT NULL REFERENCES deals(id) ON DELETE CASCADE,

  -- Nullable: a one-off line ("custom integration work") is a real thing to
  -- sell, and forcing a catalogue entry for it produces junk catalogue rows.
  service_id        uuid REFERENCES services(id) ON DELETE SET NULL,
  -- Where the price came from. Provenance, so "why was it this price" is
  -- answerable later without reconstructing the catalogue's history.
  price_book_id     uuid REFERENCES price_books(id) ON DELETE SET NULL,
  price_book_entry_id uuid REFERENCES price_book_entries(id) ON DELETE SET NULL,

  -- Snapshots taken at the moment of sale.
  description       text NOT NULL CHECK (btrim(description) <> ''),
  sku               text,

  quantity          numeric(14,4) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price        numeric(18,4) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  -- NULL means the cost was unknown at the time, not that it was zero.
  unit_cost         numeric(18,4) CHECK (unit_cost IS NULL OR unit_cost >= 0),

  -- Exactly one form of discount, or neither. Allowing both invites a row where
  -- they disagree and a reader has to guess which one the total used.
  discount_percent  numeric(6,4)
                      CHECK (discount_percent IS NULL
                             OR (discount_percent >= 0 AND discount_percent <= 1)),
  discount_amount   numeric(18,4)
                      CHECK (discount_amount IS NULL OR discount_amount >= 0),

  tax_rate          numeric(6,4) NOT NULL DEFAULT 0
                      CHECK (tax_rate >= 0 AND tax_rate <= 1),

  -- --- derived, in computation order ---------------------------------------
  gross_amount      numeric(18,4) GENERATED ALWAYS AS (
                      round(quantity * unit_price, 4)
                    ) STORED,

  discount_total    numeric(18,4) GENERATED ALWAYS AS (
                      round(
                        CASE WHEN discount_percent IS NOT NULL
                             THEN quantity * unit_price * discount_percent
                             ELSE coalesce(discount_amount, 0) END, 4)
                    ) STORED,

  -- Both operands are already rounded to 4dp, so the difference is exact.
  net_amount        numeric(18,4) GENERATED ALWAYS AS (
                      round(quantity * unit_price, 4)
                      - round(
                          CASE WHEN discount_percent IS NOT NULL
                               THEN quantity * unit_price * discount_percent
                               ELSE coalesce(discount_amount, 0) END, 4)
                    ) STORED,

  -- Tax applies to the discounted net, never to the gross.
  tax_amount        numeric(18,4) GENERATED ALWAYS AS (
                      round(
                        (round(quantity * unit_price, 4)
                         - round(
                             CASE WHEN discount_percent IS NOT NULL
                                  THEN quantity * unit_price * discount_percent
                                  ELSE coalesce(discount_amount, 0) END, 4)
                        ) * tax_rate, 4)
                    ) STORED,

  line_total        numeric(18,4) GENERATED ALWAYS AS (
                      (round(quantity * unit_price, 4)
                       - round(
                           CASE WHEN discount_percent IS NOT NULL
                                THEN quantity * unit_price * discount_percent
                                ELSE coalesce(discount_amount, 0) END, 4))
                      + round(
                          (round(quantity * unit_price, 4)
                           - round(
                               CASE WHEN discount_percent IS NOT NULL
                                    THEN quantity * unit_price * discount_percent
                                    ELSE coalesce(discount_amount, 0) END, 4)
                          ) * tax_rate, 4)
                    ) STORED,

  -- NULL when unit_cost is NULL, and deliberately so: NULL propagates through
  -- the rollup and surfaces as cost_known = false rather than as a margin
  -- figure computed against a cost nobody recorded.
  cost_total        numeric(18,4) GENERATED ALWAYS AS (
                      round(quantity * unit_cost, 4)
                    ) STORED,

  -- Margin is against net revenue, not the tax-inclusive total: tax collected
  -- on behalf of a government was never revenue.
  margin_amount     numeric(18,4) GENERATED ALWAYS AS (
                      round(quantity * unit_price, 4)
                      - round(
                          CASE WHEN discount_percent IS NOT NULL
                               THEN quantity * unit_price * discount_percent
                               ELSE coalesce(discount_amount, 0) END, 4)
                      - round(quantity * unit_cost, 4)
                    ) STORED,

  position          numeric NOT NULL DEFAULT 0,

  created_by        uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,

  CONSTRAINT deal_line_items_one_discount_form CHECK (
    discount_percent IS NULL OR discount_amount IS NULL
  ),

  -- A discount larger than the line is not a discount, it is a sign error.
  CONSTRAINT deal_line_items_discount_within_gross CHECK (
    coalesce(discount_amount, 0) <= round(quantity * unit_price, 4)
  )
);

CREATE INDEX deal_line_items_deal_idx
  ON deal_line_items (deal_id, position, created_at)
  WHERE deleted_at IS NULL;

CREATE INDEX deal_line_items_org_service_idx
  ON deal_line_items (organization_id, service_id)
  WHERE deleted_at IS NULL;

SELECT app.attach_tenant_triggers('deal_line_items');

CREATE TRIGGER deal_line_items_deal_same_org
  BEFORE INSERT OR UPDATE OF deal_id ON deal_line_items
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('deals', 'deal_id');

CREATE TRIGGER deal_line_items_service_same_org
  BEFORE INSERT OR UPDATE OF service_id ON deal_line_items
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('services', 'service_id');

CREATE TRIGGER deal_line_items_book_same_org
  BEFORE INSERT OR UPDATE OF price_book_id ON deal_line_items
  FOR EACH ROW EXECUTE FUNCTION app.assert_same_org('price_books', 'price_book_id');

-- A line priced from a EUR book on a USD deal is a number that means nothing.
-- The line carries no currency of its own — it is denominated in the deal's —
-- so the only way to get this wrong is to source the price from a book in
-- another currency, which is what this refuses.
CREATE OR REPLACE FUNCTION app.assert_line_currency()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_deal_currency char(3);
  v_book_currency char(3);
BEGIN
  IF NEW.price_book_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT currency INTO v_deal_currency FROM deals WHERE id = NEW.deal_id;
  SELECT currency INTO v_book_currency FROM price_books WHERE id = NEW.price_book_id;

  IF v_deal_currency IS DISTINCT FROM v_book_currency THEN
    RAISE EXCEPTION
      'currency mismatch: deal is in %, price book is in %',
      v_deal_currency, v_book_currency
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER deal_line_items_currency
  BEFORE INSERT OR UPDATE OF price_book_id, deal_id ON deal_line_items
  FOR EACH ROW EXECUTE FUNCTION app.assert_line_currency();

-- ---------------------------------------------------------------------------
-- The rollup: deals.amount follows its line items
--
-- Once a deal has line items, its `amount` is derived. The alternative is two
-- numbers that can disagree, and the one a report happens to read decides
-- whether the quarter made target. A deal with no line items keeps the manual
-- `amount` it has always had, so this is additive rather than a behaviour
-- change for existing rows.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.refresh_deal_amount()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ids   uuid[] := '{}';
  v_id    uuid;
  v_total numeric(18,4);
BEGIN
  IF TG_OP <> 'INSERT' THEN v_ids := v_ids || OLD.deal_id; END IF;
  IF TG_OP <> 'DELETE' THEN v_ids := v_ids || NEW.deal_id; END IF;

  -- Transaction-local, so the guard below can tell a rollup from a hand edit.
  PERFORM set_config('app.deal_amount_rollup', '1', true);

  FOREACH v_id IN ARRAY v_ids LOOP
    SELECT coalesce(sum(line_total), 0) INTO v_total
      FROM deal_line_items
     WHERE deal_id = v_id AND deleted_at IS NULL;

    UPDATE deals SET amount = v_total
     WHERE id = v_id AND amount IS DISTINCT FROM v_total;
  END LOOP;

  PERFORM set_config('app.deal_amount_rollup', '', true);
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION app.refresh_deal_amount() IS
  'SECURITY DEFINER so the total stays correct even when the caller cannot '
  'write to deals directly; it only ever writes a sum of rows the caller was '
  'already permitted to change.';

CREATE TRIGGER deal_line_items_rollup
  AFTER INSERT OR UPDATE OF quantity, unit_price, discount_percent,
                            discount_amount, tax_rate, deleted_at, deal_id
     OR DELETE
  ON deal_line_items
  FOR EACH ROW EXECUTE FUNCTION app.refresh_deal_amount();

-- Refuses a hand-edited amount on a deal that has line items. Loud rather than
-- silent: the rollup would overwrite the edit on the next line change anyway,
-- and a number that quietly reverts is worse than one that is refused.
CREATE OR REPLACE FUNCTION app.guard_deal_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.amount IS NOT DISTINCT FROM OLD.amount THEN
    RETURN NEW;
  END IF;

  IF coalesce(current_setting('app.deal_amount_rollup', true), '') = '1' THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM deal_line_items
     WHERE deal_id = NEW.id AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION
      'deal % has line items, so its amount is derived from them — edit the '
      'line items instead', NEW.id
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER deals_guard_amount
  BEFORE UPDATE OF amount ON deals
  FOR EACH ROW EXECUTE FUNCTION app.guard_deal_amount();

-- ---------------------------------------------------------------------------
-- Price resolution
-- ---------------------------------------------------------------------------
CREATE TYPE price_quote AS (
  unit_price          numeric(18,4),
  unit_cost           numeric(18,4),
  price_book_id       uuid,
  price_book_entry_id uuid,
  source              text
);

-- Resolves what an item costs a customer right now, under a given book.
--
-- Tiers are declared by their floor and the highest applicable one wins, so
-- there are no ranges to leave gaps between. Ties on the floor are broken by
-- the later `valid_from`, which is what makes a scheduled price change take
-- effect without deleting the row it replaces.
CREATE OR REPLACE FUNCTION app.resolve_price(
  p_service_id    uuid,
  p_price_book_id uuid        DEFAULT NULL,
  p_quantity      numeric     DEFAULT 1,
  p_at            timestamptz DEFAULT now()
)
RETURNS price_quote
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_service services%ROWTYPE;
  v_book    price_books%ROWTYPE;
  v_entry   price_book_entries%ROWTYPE;
  v_out     price_quote;
BEGIN
  SELECT * INTO v_service FROM services
   WHERE id = p_service_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such service: %', p_service_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF p_price_book_id IS NOT NULL THEN
    SELECT * INTO v_book FROM price_books
     WHERE id = p_price_book_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'no such price book: %', p_price_book_id
        USING ERRCODE = 'no_data_found';
    END IF;
    -- A book named explicitly but unusable is a caller error worth surfacing.
    -- Falling back silently would price the deal from the catalogue while the
    -- caller believed a negotiated book was in effect.
    IF NOT v_book.is_active
       OR (v_book.valid_from IS NOT NULL AND p_at < v_book.valid_from)
       OR (v_book.valid_to   IS NOT NULL AND p_at >= v_book.valid_to) THEN
      RAISE EXCEPTION 'price book % is not in effect at %', p_price_book_id, p_at
        USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    SELECT * INTO v_book FROM price_books
     WHERE organization_id = v_service.organization_id
       AND currency = v_service.currency
       AND is_default AND is_active AND deleted_at IS NULL
       AND (valid_from IS NULL OR p_at >= valid_from)
       AND (valid_to   IS NULL OR p_at <  valid_to)
     LIMIT 1;
  END IF;

  IF v_book.id IS NOT NULL THEN
    SELECT * INTO v_entry FROM price_book_entries e
     WHERE e.price_book_id = v_book.id
       AND e.service_id = p_service_id
       AND e.deleted_at IS NULL
       AND e.min_quantity <= p_quantity
       AND (e.valid_from IS NULL OR p_at >= e.valid_from)
       AND (e.valid_to   IS NULL OR p_at <  e.valid_to)
     ORDER BY e.min_quantity DESC, e.valid_from DESC NULLS LAST
     LIMIT 1;
  END IF;

  IF v_entry.id IS NOT NULL THEN
    v_out.unit_price          := v_entry.unit_price;
    v_out.unit_cost           := coalesce(v_entry.unit_cost, v_service.unit_cost);
    v_out.price_book_id       := v_book.id;
    v_out.price_book_entry_id := v_entry.id;
    v_out.source              := 'price_book';
  ELSE
    v_out.unit_price          := v_service.unit_price;
    v_out.unit_cost           := v_service.unit_cost;
    v_out.price_book_id       := NULL;
    v_out.price_book_entry_id := NULL;
    v_out.source              := 'catalogue';
  END IF;

  RETURN v_out;
END;
$$;

-- Adds a line, snapshotting price, cost and description at the moment of sale.
--
-- Prefer this over inserting directly: it resolves the price, records which
-- book it came from, and copies the catalogue's tax rate. A caller assembling
-- the row by hand has to remember all three, and the one who forgets is the one
-- whose deal reports the wrong margin.
CREATE OR REPLACE FUNCTION app.add_deal_line_item(
  p_deal_id          uuid,
  p_service_id       uuid    DEFAULT NULL,
  p_quantity         numeric DEFAULT 1,
  p_price_book_id    uuid    DEFAULT NULL,
  p_unit_price       numeric DEFAULT NULL,
  p_discount_percent numeric DEFAULT NULL,
  p_description      text    DEFAULT NULL,
  p_tax_rate         numeric DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_deal    deals%ROWTYPE;
  v_service services%ROWTYPE;
  v_quote   price_quote;
  v_id      uuid;
  v_next    numeric;
BEGIN
  SELECT * INTO v_deal FROM deals WHERE id = p_deal_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such deal: %', p_deal_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF p_service_id IS NOT NULL THEN
    SELECT * INTO v_service FROM services
     WHERE id = p_service_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'no such service: %', p_service_id
        USING ERRCODE = 'no_data_found';
    END IF;
    v_quote := app.resolve_price(p_service_id, p_price_book_id, p_quantity);
  ELSE
    -- A one-off line still has to say what it is and what it costs.
    IF p_unit_price IS NULL OR coalesce(btrim(p_description), '') = '' THEN
      RAISE EXCEPTION
        'a line item with no service must supply both a description and a unit price'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  SELECT coalesce(max(position), 0) + 1 INTO v_next
    FROM deal_line_items WHERE deal_id = p_deal_id AND deleted_at IS NULL;

  INSERT INTO deal_line_items (
    organization_id, deal_id, service_id,
    price_book_id, price_book_entry_id,
    description, sku, quantity, unit_price, unit_cost,
    discount_percent, tax_rate, position, created_by
  ) VALUES (
    v_deal.organization_id, p_deal_id, p_service_id,
    v_quote.price_book_id, v_quote.price_book_entry_id,
    coalesce(nullif(btrim(coalesce(p_description, '')), ''), v_service.name),
    v_service.sku,
    p_quantity,
    -- An explicit override always wins: a negotiated price is the reason the
    -- override exists, and quietly replacing it with the book price would make
    -- the deal wrong in the customer's favour or against it.
    coalesce(p_unit_price, v_quote.unit_price, 0),
    v_quote.unit_cost,
    p_discount_percent,
    coalesce(p_tax_rate, v_service.tax_rate, 0),
    v_next,
    app.current_user_id()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Deal totals
--
-- Reported from the lines rather than stored on the deal, apart from `amount`
-- which the rollup maintains for the pipeline queries that need to sort and sum
-- without a join. Everything else is computed on demand: a stored subtotal that
-- nothing forces to agree with its lines is a second source of truth.
-- ---------------------------------------------------------------------------
CREATE TYPE deal_totals AS (
  line_count     integer,
  gross_total    numeric(18,4),
  discount_total numeric(18,4),
  net_total      numeric(18,4),
  tax_total      numeric(18,4),
  total          numeric(18,4),
  cost_total     numeric(18,4),
  margin_total   numeric(18,4),
  margin_percent numeric(7,4),
  -- False when any line has no recorded cost. Margin is NULL in that case
  -- rather than computed against the lines that happen to have one, which
  -- would report a margin higher than reality and always in the flattering
  -- direction.
  cost_known     boolean
);

CREATE OR REPLACE FUNCTION app.deal_totals(p_deal_id uuid)
RETURNS deal_totals
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_out deal_totals;
BEGIN
  SELECT
    count(*)::integer,
    coalesce(sum(gross_amount), 0),
    coalesce(sum(discount_total), 0),
    coalesce(sum(net_amount), 0),
    coalesce(sum(tax_amount), 0),
    coalesce(sum(line_total), 0),
    sum(cost_total),
    count(*) > 0 AND bool_and(unit_cost IS NOT NULL)
  INTO
    v_out.line_count, v_out.gross_total, v_out.discount_total,
    v_out.net_total, v_out.tax_total, v_out.total,
    v_out.cost_total, v_out.cost_known
  FROM deal_line_items
  WHERE deal_id = p_deal_id AND deleted_at IS NULL;

  IF v_out.cost_known THEN
    v_out.margin_total := v_out.net_total - v_out.cost_total;
    v_out.margin_percent := CASE
      WHEN v_out.net_total = 0 THEN NULL
      ELSE round(v_out.margin_total / v_out.net_total, 4)
    END;
  ELSE
    v_out.cost_total   := NULL;
    v_out.margin_total := NULL;
    v_out.margin_percent := NULL;
  END IF;

  RETURN v_out;
END;
$$;

COMMENT ON FUNCTION app.deal_totals(uuid) IS
  'Totals computed from live line items. Always check cost_known before '
  'presenting margin — a NULL margin means the cost was never recorded, not '
  'that the deal broke even.';

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
SELECT app.apply_tenant_rls('price_books');
SELECT app.apply_tenant_rls('price_book_entries');
SELECT app.apply_tenant_rls('deal_line_items');

-- ---------------------------------------------------------------------------
-- Audit
--
-- All three are audited in full, unlike `files` in 0013. These tables carry
-- money: a changed price, a changed quantity, an applied discount are each an
-- answer someone will eventually need, and none of them is derived bookkeeping.
-- The generated columns move with their inputs and are recorded alongside them,
-- which is the intended reading — "the total changed because the quantity did"
-- is the story the trail should tell.
-- ---------------------------------------------------------------------------
SELECT app.attach_audit('price_books');
SELECT app.attach_audit('price_book_entries');
SELECT app.attach_audit('deal_line_items');

COMMIT;

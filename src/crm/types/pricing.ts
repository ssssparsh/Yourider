/**
 * Price books, deal line items, and margin.
 *
 * Mirrors src/db/migrations/0014_pricing.sql.
 *
 * Everything here is money, so every derived amount is a `Numeric` — a string,
 * not a number. See scalars.ts: converting these to `number` to make arithmetic
 * convenient reintroduces exactly the precision loss `numeric` was chosen to
 * prevent. Push the arithmetic into SQL, where the schema already computes it
 * as generated columns.
 *
 * 0014 introduces no new database enums, so there is no registry to add to
 * verify.ts — its new types are composites (`price_quote`, `deal_totals`),
 * which the drift check does not cover.
 */

import type { CurrencyCode, Id, Numeric } from './scalars.js';
import type { DealId, OrganizationId, ServiceId, UserId } from './entities.js';

// ---------------------------------------------------------------------------
// Identifiers
// ---------------------------------------------------------------------------

export type PriceBookId = Id<'PriceBook'>;
export type PriceBookEntryId = Id<'PriceBookEntry'>;
export type DealLineItemId = Id<'DealLineItem'>;

// ---------------------------------------------------------------------------
// Price books
// ---------------------------------------------------------------------------

/**
 * A named set of prices in one currency.
 *
 * The default is per *currency*, not per organization: a tenant selling in
 * three currencies needs three defaults, and a single global one would force
 * every non-base-currency deal to name a book explicitly.
 */
export interface PriceBook {
  readonly id: PriceBookId;
  readonly organization_id: OrganizationId;
  readonly name: string;
  readonly code: string | null;
  readonly description: string | null;
  readonly currency: CurrencyCode;
  readonly is_default: boolean;
  readonly is_active: boolean;
  readonly valid_from: Date | null;
  readonly valid_to: Date | null;
  readonly created_by: UserId | null;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

/**
 * One item's price in one book, optionally for a volume tier and a date window.
 *
 * Tiers are declared by their floor (`min_quantity`) and the highest applicable
 * one wins, so there are no ranges to leave gaps between. The entry carries no
 * currency of its own — the book's currency is the only answer, so the two
 * cannot disagree.
 */
export interface PriceBookEntry {
  readonly id: PriceBookEntryId;
  readonly organization_id: OrganizationId;
  readonly price_book_id: PriceBookId;
  readonly service_id: ServiceId;
  readonly unit_price: Numeric;
  /** Overrides the catalogue cost for this book. NULL falls through. */
  readonly unit_cost: Numeric | null;
  /** This row applies from this quantity upward. */
  readonly min_quantity: Numeric;
  readonly valid_from: Date | null;
  readonly valid_to: Date | null;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

/** Result of `app.resolve_price()`. */
export interface PriceQuote {
  readonly unit_price: Numeric;
  /** NULL when no cost is recorded anywhere — unknown, not zero. */
  readonly unit_cost: Numeric | null;
  readonly price_book_id: PriceBookId | null;
  readonly price_book_entry_id: PriceBookEntryId | null;
  readonly source: PriceSource;
}

export const PriceSource = {
  /** Matched a price book entry. */
  PriceBook: 'price_book',
  /** No book applied; the catalogue's own unit_price was used. */
  Catalogue: 'catalogue',
} as const;
export type PriceSource = (typeof PriceSource)[keyof typeof PriceSource];

// ---------------------------------------------------------------------------
// Deal line items
// ---------------------------------------------------------------------------

/**
 * What was sold, at what price, at what discount, at what margin.
 *
 * Price, cost, description and SKU are SNAPSHOT at the moment of sale rather
 * than read through to the catalogue: a catalogue price change must not
 * silently rewrite what a closed deal was sold for.
 *
 * The derived amounts are generated columns defined so that
 * `net_amount + tax_amount === line_total` exactly. An invoice whose lines do
 * not add up to its total is the bug that shape exists to make impossible.
 */
export interface DealLineItem {
  readonly id: DealLineItemId;
  readonly organization_id: OrganizationId;
  readonly deal_id: DealId;
  /** NULL for a one-off line that has no catalogue entry. */
  readonly service_id: ServiceId | null;
  /** Provenance: which book this price came from, if any. */
  readonly price_book_id: PriceBookId | null;
  readonly price_book_entry_id: PriceBookEntryId | null;

  readonly description: string;
  readonly sku: string | null;

  readonly quantity: Numeric;
  readonly unit_price: Numeric;
  /** NULL means the cost was unknown at the time, not that it was zero. */
  readonly unit_cost: Numeric | null;

  /** 0..1. Mutually exclusive with discount_amount, enforced by CHECK. */
  readonly discount_percent: Numeric | null;
  readonly discount_amount: Numeric | null;
  readonly tax_rate: Numeric;

  // --- generated, in computation order -------------------------------------
  readonly gross_amount: Numeric;
  readonly discount_total: Numeric;
  readonly net_amount: Numeric;
  /** Applies to the discounted net, never to the gross. */
  readonly tax_amount: Numeric;
  readonly line_total: Numeric;
  /** NULL when unit_cost is NULL — the NULL is the signal. */
  readonly cost_total: Numeric | null;
  /** Against net revenue, not the tax-inclusive total. NULL when cost is. */
  readonly margin_amount: Numeric | null;

  readonly position: Numeric;
  readonly created_by: UserId | null;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly deleted_at: Date | null;
}

/**
 * Result of `app.deal_totals()`.
 *
 * **Always check `cost_known` before presenting margin.** A NULL margin means
 * the cost was never recorded, not that the deal broke even — reporting the
 * margin of only the lines that happen to carry a cost overstates it, and
 * always in the flattering direction.
 */
export interface DealTotals {
  readonly line_count: number;
  readonly gross_total: Numeric;
  readonly discount_total: Numeric;
  readonly net_total: Numeric;
  readonly tax_total: Numeric;
  readonly total: Numeric;
  readonly cost_total: Numeric | null;
  readonly margin_total: Numeric | null;
  /** Margin as a fraction of net. NULL when net is zero or cost is unknown. */
  readonly margin_percent: Numeric | null;
  readonly cost_known: boolean;
}

// ---------------------------------------------------------------------------
// Insert and argument shapes
// ---------------------------------------------------------------------------

export interface PriceBookInsert {
  name: string;
  currency: CurrencyCode;
  code?: string | null;
  description?: string | null;
  is_default?: boolean;
  is_active?: boolean;
  valid_from?: Date | null;
  valid_to?: Date | null;
  created_by?: UserId | null;
}

export interface PriceBookEntryInsert {
  price_book_id: PriceBookId;
  service_id: ServiceId;
  unit_price: Numeric;
  unit_cost?: Numeric | null;
  min_quantity?: Numeric;
  valid_from?: Date | null;
  valid_to?: Date | null;
}

/**
 * Arguments to `app.add_deal_line_item()`.
 *
 * Prefer this over inserting into `deal_line_items` directly: it resolves the
 * price, records which book it came from, and copies the catalogue's tax rate.
 * A caller assembling the row by hand has to remember all three, and the one
 * who forgets is the one whose deal reports the wrong margin.
 *
 * With no `service_id`, both `description` and `unit_price` are required — a
 * one-off line still has to say what it is and what it costs.
 */
export interface AddDealLineItemArgs {
  deal_id: DealId;
  service_id?: ServiceId | null;
  quantity?: Numeric;
  price_book_id?: PriceBookId | null;
  /** An explicit override always wins over the resolved book price. */
  unit_price?: Numeric | null;
  discount_percent?: Numeric | null;
  description?: string | null;
  tax_rate?: Numeric | null;
}

/**
 * `deals.amount` is derived once a deal has line items, and the database
 * refuses a hand edit rather than silently overwriting it on the next rollup.
 * A deal with no line items keeps the manual amount it has always had.
 */
export const DEAL_AMOUNT_IS_DERIVED_WHEN_ITEMISED = true;

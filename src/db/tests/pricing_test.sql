-- pricing_test.sql
-- Exercises the catalogue cost basis, price books, and deal line items.
--
-- Money arithmetic is where a CRM quietly loses trust: a total that does not
-- equal the sum of its parts, tax charged on the pre-discount amount, a margin
-- computed against costs that were never recorded. Each of those is asserted
-- here with numbers chosen so the expected answer is checkable by hand.
--
-- Requires the fixture from functional_test.sql (org-a and its pipeline).
--
--   psql -d yourider -v ON_ERROR_STOP=1 -f src/db/tests/pricing_test.sql

\set ON_ERROR_STOP on

DO $$
DECLARE
  v_org       uuid;
  v_org_b     uuid;
  v_user      uuid;
  v_pipeline  uuid;
  v_stage     uuid;
  v_deal      uuid;
  v_deal_eur  uuid;
  v_svc       uuid;
  v_svc_nocost uuid;
  v_svc_foreign uuid;
  v_book      uuid;
  v_book_eur  uuid;
  v_book_old  uuid;
  v_entry     uuid;
  v_line_a    uuid;
  v_line_b    uuid;
  v_quote     price_quote;
  v_totals    deal_totals;
  v_amount    numeric(18,4);
  v_n         numeric;
  v_row       deal_line_items%ROWTYPE;
  v_count     int;
BEGIN
  SELECT id INTO v_org   FROM organizations WHERE slug = 'org-a';
  SELECT id INTO v_org_b FROM organizations WHERE slug = 'org-b';
  SELECT id INTO v_user  FROM users WHERE email = 'a@example.com';
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'fixture missing: run functional_test.sql first';
  END IF;

  PERFORM set_config('app.current_org_id', v_org::text, false);
  PERFORM set_config('app.current_user_id', v_user::text, false);

  SELECT p.id, s.id INTO v_pipeline, v_stage
    FROM pipelines p
    JOIN pipeline_stages s ON s.pipeline_id = p.id AND s.kind = 'open'
   WHERE p.organization_id = v_org AND p.entity_type = 'deal'
   ORDER BY s.position LIMIT 1;

  INSERT INTO deals (organization_id, name, pipeline_id, stage_id, currency)
    VALUES (v_org, 'Pricing test deal', v_pipeline, v_stage, 'USD')
    RETURNING id INTO v_deal;

  -- =========================================================================
  RAISE NOTICE '--- 1. catalogue cost basis ---';
  -- =========================================================================
  INSERT INTO services (organization_id, name, sku, unit_price, unit_cost,
                        currency, tax_rate)
    VALUES (v_org, 'Fleet telemetry unit', 'TEL-1', 100.0000, 60.0000, 'USD', 0.2000)
    RETURNING id INTO v_svc;

  INSERT INTO services (organization_id, name, sku, unit_price, currency, tax_rate)
    VALUES (v_org, 'Bespoke integration', 'INT-1', 49.9900, 'USD', 0.0750)
    RETURNING id INTO v_svc_nocost;
  RAISE NOTICE '  ok: catalogue carries a cost basis (and may omit it)';

  -- =========================================================================
  RAISE NOTICE '--- 2. price books ---';
  -- =========================================================================
  INSERT INTO price_books (organization_id, name, code, currency, is_default)
    VALUES (v_org, 'US list', 'US-LIST', 'USD', true) RETURNING id INTO v_book;

  INSERT INTO price_books (organization_id, name, code, currency, is_default)
    VALUES (v_org, 'EU list', 'EU-LIST', 'EUR', true) RETURNING id INTO v_book_eur;
  RAISE NOTICE '  ok: a default book per currency, not per organization';

  BEGIN
    INSERT INTO price_books (organization_id, name, currency, is_default)
      VALUES (v_org, 'US list 2', 'USD', true);
    RAISE EXCEPTION 'FAIL: two default books accepted for one currency';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '  ok: only one default per currency';
  END;

  -- Volume tiers, declared by their floor.
  INSERT INTO price_book_entries (organization_id, price_book_id, service_id,
                                  unit_price, min_quantity)
    VALUES (v_org, v_book, v_svc, 100.0000, 0);
  INSERT INTO price_book_entries (organization_id, price_book_id, service_id,
                                  unit_price, min_quantity)
    VALUES (v_org, v_book, v_svc, 90.0000, 10);
  INSERT INTO price_book_entries (organization_id, price_book_id, service_id,
                                  unit_price, min_quantity)
    VALUES (v_org, v_book, v_svc, 80.0000, 100)
    RETURNING id INTO v_entry;
  RAISE NOTICE '  ok: three volume tiers declared';

  -- =========================================================================
  RAISE NOTICE '--- 3. price resolution ---';
  -- =========================================================================
  v_quote := app.resolve_price(v_svc, v_book, 5);
  IF v_quote.unit_price <> 100.0000 OR v_quote.source <> 'price_book' THEN
    RAISE EXCEPTION 'FAIL: qty 5 resolved to % from %', v_quote.unit_price, v_quote.source;
  END IF;

  v_quote := app.resolve_price(v_svc, v_book, 10);
  IF v_quote.unit_price <> 90.0000 THEN
    RAISE EXCEPTION 'FAIL: qty 10 resolved to %', v_quote.unit_price;
  END IF;

  v_quote := app.resolve_price(v_svc, v_book, 250);
  IF v_quote.unit_price <> 80.0000 THEN
    RAISE EXCEPTION 'FAIL: qty 250 resolved to %', v_quote.unit_price;
  END IF;
  RAISE NOTICE '  ok: the highest applicable tier wins (100 / 90 / 80)';

  -- The cost comes from the catalogue when the book does not override it.
  IF v_quote.unit_cost <> 60.0000 THEN
    RAISE EXCEPTION 'FAIL: cost resolved to %', v_quote.unit_cost;
  END IF;
  RAISE NOTICE '  ok: cost falls through from the catalogue';

  -- A scheduled price change does not apply before its start.
  INSERT INTO price_book_entries (organization_id, price_book_id, service_id,
                                  unit_price, min_quantity, valid_from)
    VALUES (v_org, v_book, v_svc, 70.0000, 0, now() + interval '30 days');
  v_quote := app.resolve_price(v_svc, v_book, 5);
  IF v_quote.unit_price <> 100.0000 THEN
    RAISE EXCEPTION 'FAIL: a future price applied today (%)', v_quote.unit_price;
  END IF;
  v_quote := app.resolve_price(v_svc, v_book, 5, now() + interval '31 days');
  IF v_quote.unit_price <> 70.0000 THEN
    RAISE EXCEPTION 'FAIL: the future price did not apply later (%)', v_quote.unit_price;
  END IF;
  RAISE NOTICE '  ok: effective dating schedules a price without deleting the old one';

  -- No book for this item: the catalogue is the fallback, and says so.
  v_quote := app.resolve_price(v_svc_nocost, v_book, 1);
  IF v_quote.unit_price <> 49.9900 OR v_quote.source <> 'catalogue' THEN
    RAISE EXCEPTION 'FAIL: catalogue fallback resolved to % from %',
      v_quote.unit_price, v_quote.source;
  END IF;
  RAISE NOTICE '  ok: falls back to the catalogue and reports the source';

  -- A book named explicitly but not in effect is a caller error, not a silent
  -- fallback — otherwise the deal is priced from the catalogue while the caller
  -- believes a negotiated book applied.
  INSERT INTO price_books (organization_id, name, currency, is_active)
    VALUES (v_org, 'Retired 2024', 'USD', false) RETURNING id INTO v_book_old;
  BEGIN
    PERFORM app.resolve_price(v_svc, v_book_old, 1);
    RAISE EXCEPTION 'FAIL: an inactive book was used';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: an explicitly named inactive book is refused, not ignored';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 4. line items snapshot the sale ---';
  -- =========================================================================
  v_line_a := app.add_deal_line_item(v_deal, v_svc, 3, v_book, NULL, 0.1000);
  SELECT * INTO v_row FROM deal_line_items WHERE id = v_line_a;

  IF v_row.unit_price <> 100.0000 OR v_row.unit_cost <> 60.0000 THEN
    RAISE EXCEPTION 'FAIL: snapshot took price % cost %', v_row.unit_price, v_row.unit_cost;
  END IF;
  IF v_row.sku <> 'TEL-1' OR v_row.description <> 'Fleet telemetry unit' THEN
    RAISE EXCEPTION 'FAIL: sku/description not snapshotted';
  END IF;
  IF v_row.price_book_id <> v_book OR v_row.price_book_entry_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: price provenance not recorded';
  END IF;
  RAISE NOTICE '  ok: price, cost, sku and provenance are snapshotted';

  -- Repricing the catalogue must not rewrite what a deal was sold for.
  UPDATE services SET unit_price = 130.0000 WHERE id = v_svc;
  SELECT unit_price INTO v_n FROM deal_line_items WHERE id = v_line_a;
  IF v_n <> 100.0000 THEN
    RAISE EXCEPTION 'FAIL: a catalogue change rewrote a sold line (%)', v_n;
  END IF;
  RAISE NOTICE '  ok: a catalogue price change does not rewrite history';

  -- =========================================================================
  RAISE NOTICE '--- 5. line arithmetic ---';
  -- =========================================================================
  -- qty 3 x 100 = 300 gross; 10% = 30 discount; net 270; 20% tax = 54; total 324.
  IF v_row.gross_amount <> 300.0000 OR v_row.discount_total <> 30.0000
     OR v_row.net_amount <> 270.0000 OR v_row.tax_amount <> 54.0000
     OR v_row.line_total <> 324.0000 THEN
    RAISE EXCEPTION 'FAIL: line A computed % / % / % / % / %',
      v_row.gross_amount, v_row.discount_total, v_row.net_amount,
      v_row.tax_amount, v_row.line_total;
  END IF;
  RAISE NOTICE '  ok: 3 x 100 less 10%% plus 20%% tax = 324.0000';

  -- Tax lands on the discounted net, never on the gross: at 20% of 300 the tax
  -- would be 60, and the customer would be charged for a discount they got.
  IF v_row.tax_amount = round(v_row.gross_amount * 0.20, 4) THEN
    RAISE EXCEPTION 'FAIL: tax was charged on the gross';
  END IF;
  RAISE NOTICE '  ok: tax applies to the discounted net, not the gross';

  -- A line whose parts do not add up to its total is the bug this shape exists
  -- to prevent, so it is asserted on a case that does not divide evenly.
  v_line_b := app.add_deal_line_item(
    v_deal, v_svc_nocost, 2, NULL, NULL, NULL, NULL, NULL);
  UPDATE deal_line_items SET discount_amount = 9.9900 WHERE id = v_line_b;
  SELECT * INTO v_row FROM deal_line_items WHERE id = v_line_b;

  IF v_row.net_amount + v_row.tax_amount <> v_row.line_total THEN
    RAISE EXCEPTION 'FAIL: % + % <> %',
      v_row.net_amount, v_row.tax_amount, v_row.line_total;
  END IF;
  IF v_row.gross_amount - v_row.discount_total <> v_row.net_amount THEN
    RAISE EXCEPTION 'FAIL: gross - discount <> net';
  END IF;
  RAISE NOTICE '  ok: net + tax = total exactly, on a rate that does not divide evenly';

  -- =========================================================================
  RAISE NOTICE '--- 6. discounts are validated ---';
  -- =========================================================================
  BEGIN
    UPDATE deal_line_items SET discount_percent = 0.1000 WHERE id = v_line_b;
    RAISE EXCEPTION 'FAIL: both discount forms accepted on one line';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a line carries one form of discount, not two';
  END;

  BEGIN
    INSERT INTO deal_line_items (organization_id, deal_id, description,
                                 quantity, unit_price, discount_amount)
      VALUES (v_org, v_deal, 'Over-discounted', 1, 10.0000, 25.0000);
    RAISE EXCEPTION 'FAIL: a discount larger than the line was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a discount cannot exceed the line';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 7. the deal amount follows its lines ---';
  -- =========================================================================
  v_totals := app.deal_totals(v_deal);
  SELECT amount INTO v_amount FROM deals WHERE id = v_deal;

  IF v_amount <> v_totals.total THEN
    RAISE EXCEPTION 'FAIL: deals.amount % <> line total %', v_amount, v_totals.total;
  END IF;
  RAISE NOTICE '  ok: deals.amount (%) equals the sum of its lines', v_amount;

  -- A hand edit is refused rather than silently overwritten by the next rollup.
  BEGIN
    UPDATE deals SET amount = 1.0000 WHERE id = v_deal;
    RAISE EXCEPTION 'FAIL: a derived amount was hand-edited';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: an itemised deal refuses a hand-edited amount';
  END;

  -- Soft-deleting a line moves the total.
  UPDATE deal_line_items SET deleted_at = now() WHERE id = v_line_b;
  SELECT amount INTO v_amount FROM deals WHERE id = v_deal;
  IF v_amount <> 324.0000 THEN
    RAISE EXCEPTION 'FAIL: removing a line left the amount at %', v_amount;
  END IF;
  RAISE NOTICE '  ok: removing a line updates the deal in the same transaction';

  -- =========================================================================
  RAISE NOTICE '--- 8. margin ---';
  -- =========================================================================
  v_totals := app.deal_totals(v_deal);
  IF NOT v_totals.cost_known THEN
    RAISE EXCEPTION 'FAIL: cost should be known — the only live line has one';
  END IF;
  -- net 270 less cost 180 = 90, which is 33.33% of net. Margin is against net,
  -- not the tax-inclusive total: tax collected for a government is not revenue.
  IF v_totals.margin_total <> 90.0000 OR v_totals.cost_total <> 180.0000 THEN
    RAISE EXCEPTION 'FAIL: margin % on cost %', v_totals.margin_total, v_totals.cost_total;
  END IF;
  IF v_totals.margin_percent <> 0.3333 THEN
    RAISE EXCEPTION 'FAIL: margin percent %', v_totals.margin_percent;
  END IF;
  RAISE NOTICE '  ok: margin 90.0000 on net 270.0000 = 33.33%%, excluding tax';

  -- One costless line makes the whole deal's margin unknown. Reporting the
  -- margin of the lines that happen to have a cost would overstate it, and
  -- always in the flattering direction.
  UPDATE deal_line_items SET deleted_at = NULL WHERE id = v_line_b;
  v_totals := app.deal_totals(v_deal);
  IF v_totals.cost_known OR v_totals.margin_total IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: margin reported despite an unpriced cost';
  END IF;
  RAISE NOTICE '  ok: one line with no cost makes the margin unknown, not optimistic';

  UPDATE deal_line_items SET unit_cost = 20.0000 WHERE id = v_line_b;
  v_totals := app.deal_totals(v_deal);
  IF NOT v_totals.cost_known THEN
    RAISE EXCEPTION 'FAIL: cost still unknown after being recorded';
  END IF;
  RAISE NOTICE '  ok: recording the missing cost makes the margin knowable again';

  -- =========================================================================
  RAISE NOTICE '--- 9. currency ---';
  -- =========================================================================
  INSERT INTO price_book_entries (organization_id, price_book_id, service_id,
                                  unit_price, min_quantity)
    VALUES (v_org, v_book_eur, v_svc, 95.0000, 0);
  BEGIN
    PERFORM app.add_deal_line_item(v_deal, v_svc, 1, v_book_eur);
    RAISE EXCEPTION 'FAIL: a EUR-priced line landed on a USD deal';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a price book in another currency is refused';
  END;

  -- =========================================================================
  RAISE NOTICE '--- 10. one-off lines and guards ---';
  -- =========================================================================
  BEGIN
    PERFORM app.add_deal_line_item(v_deal, NULL, 1);
    RAISE EXCEPTION 'FAIL: a nameless, priceless line was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '  ok: a line with no service must state what it is and costs';
  END;

  PERFORM app.add_deal_line_item(
    v_deal, NULL, 1, NULL, 500.0000, NULL, 'Custom onboarding');
  RAISE NOTICE '  ok: a one-off line needs no catalogue entry';

  -- Cross-tenant: a line on this deal cannot reference another tenant's item.
  -- The foreign row is created here rather than assumed: an INSERT ... SELECT
  -- that matches nothing inserts nothing and would pass this assertion without
  -- ever exercising the guard.
  INSERT INTO services (organization_id, name, unit_price, currency)
    VALUES (v_org_b, 'Foreign catalogue item', 10.0000, 'EUR')
    RETURNING id INTO v_svc_foreign;

  BEGIN
    INSERT INTO deal_line_items (organization_id, deal_id, service_id,
                                 description, quantity, unit_price)
      VALUES (v_org, v_deal, v_svc_foreign, 'Foreign item', 1, 10.0000);
    RAISE EXCEPTION 'FAIL: cross-tenant service referenced';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE '  ok: cross-tenant catalogue reference refused';
  END;

  -- A deal with no lines keeps the manual amount it has always had.
  SELECT count(*) INTO v_count FROM deal_line_items
   WHERE deal_id = v_deal AND deleted_at IS NULL;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'FAIL: fixture lost its line items';
  END IF;

  INSERT INTO deals (organization_id, name, pipeline_id, stage_id, amount)
    VALUES (v_org, 'Unitemised deal', v_pipeline, v_stage, 5000.0000)
    RETURNING id INTO v_deal_eur;
  UPDATE deals SET amount = 7500.0000 WHERE id = v_deal_eur;
  SELECT amount INTO v_amount FROM deals WHERE id = v_deal_eur;
  IF v_amount <> 7500.0000 THEN
    RAISE EXCEPTION 'FAIL: an unitemised deal lost its manual amount (%)', v_amount;
  END IF;
  RAISE NOTICE '  ok: a deal with no line items keeps a manual amount';

  RAISE NOTICE '';
  RAISE NOTICE '=== ALL PRICING ASSERTIONS PASSED ===';
END;
$$;

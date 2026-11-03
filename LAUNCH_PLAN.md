# Cradlebaby Launch Plan

Store: Cradlebaby (`twjah9-dz.myshopify.com`), India, INR, Basic plan, theme Horizon.
Connected to Claude through the Shopify connector on 2026-11-03.

Every item marked **[owner]** changes the live store. Claude prepares it, the owner says "yes", then it is done.

## Audit (2026-11-03, read-only)

| Area | Found | Problem |
|---|---|---|
| Products | 4 "Example product" ACTIVE at Rs 100, 1 empty draft | Fake products are live on the store |
| Collections | "Home page", "Vehicles and Parts example products" | Car demo collection on a baby store |
| Apps | Zendrop, Dropdash, India COD Dropshipping | 3 dropship apps, all with write access to orders, products, shipping. Overlap and risk |
| Shipping, India | One flat rate, Rs 379 | Too high for a Rs 999 product. Will kill sales |
| Shipping, International | Rs 1,800, 28 countries | Store sells only in INR. Not needed at launch |
| Shipping, Zendrop profile | Free shipping, worldwide | Can clash with the India rates |
| Policies | Only Privacy policy | Refund, Shipping, Terms, Contact missing. Meta and payment gateways need them |
| Domain | Only `.myshopify.com` | Low trust, weak for Meta ads |
| Themes | Horizon live, 4 unused | Fine. Unused ones can stay |

## Phase 0: Clean up (owner approval, 15 minutes)

1. **[owner]** Archive the 4 example products and the empty draft.
2. **[owner]** Delete the "Vehicles and Parts example products" collection.
3. **[owner]** Keep one dropship app, uninstall the other two. For India COD orders, an India-based supplier app ships faster than Zendrop.
4. **[owner]** Turn off the International shipping zone.
5. **[owner]** Remove the Zendrop shipping profile if Zendrop is uninstalled.
6. **[owner]** Set the India shipping rates. Suggested: free above Rs 599, Rs 49 below. Final number depends on the courier rate card.

## Phase 1: Foundations

| Task | Who | Notes |
|---|---|---|
| Buy a domain | Owner | Shopify connector can check availability and price |
| Refund, Shipping, Terms, Contact policies | Claude drafts, **[owner]** approves | |
| Payment gateway (Razorpay or Cashfree) with UPI and COD | Owner | Needs PAN, bank account, GSTIN if registered |
| GST and invoice settings | Owner + CA | Confirm GST registration need with a CA |
| 2-step verification on the login email | Owner | |
| Shipping and COD app (for example Shiprocket) | **[owner]** | Gets real courier rates for Phase 0 step 6 |

## Phase 2: Products

- Niche: baby and kids (matches the brand name). Start with one narrow line, for example ISI-marked learning toys for ages 1 to 5.
- Toys for children under 14 need BIS certification and the ISI mark. Ask every supplier for the certificate.
- Non-electronic toys: GST 5%. Electronic toys: 18%. Baby skincare needs a cosmetics licence, so avoid it at launch.
- Pick 3 test products. Claude creates them as **drafts** with title, description, images, price.
- Price for a 20% net margin. Use bundles to push the average order to Rs 1,499 or more.

## Phase 3: Meta ads

1. Meta Business portfolio, Facebook Page, Instagram account (owner).
2. **[owner]** Install the "Facebook & Instagram" app on Shopify, connect the Pixel and Conversions API.
3. Verify the domain in Meta Business settings.
4. Claude writes the ad scripts and copy. Owner shoots or sources the videos.
5. **[owner]** Test: Rs 1,000 a day, 7 days, 3 products. Go on to stock or scale only if add-to-cart costs under Rs 100.

## Phase 4: Daily running

- Daily briefing from Claude: orders, unfulfilled orders, COD returns, stock.
- Customer messages: Claude drafts replies, the owner sends.
- Weekly: profit check (sales minus product, shipping, ads, returns).

## Working from mobile and desktop

| Device | Use |
|---|---|
| Phone | Shopify app for orders and notifications. Claude app (chat with the Shopify connector) for questions, drafts, approvals |
| Desktop | Shopify admin for setup work. Claude app or claude.ai for planning. Claude Code (this repo) for automations |

Owner rules live in this repo's `CLAUDE.md`. Plain Claude chats do not read it. Copy section 2 and 3 of `CLAUDE.md` into a claude.ai Project's instructions, then use that Project on phone and desktop.

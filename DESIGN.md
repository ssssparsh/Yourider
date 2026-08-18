<!-- yourider:design-schema 1 -->

# Design Tokens

Machine-parseable design tokens for Yourider's `/src/interfaces` schema-driven
renderers. This is the single source of truth for color/type/spacing — the UI
should read from these tokens, not hardcode values inline. Keep this in sync
with `PRODUCT.md`'s brand personality and anti-references; if a token
contradicts an anti-reference, the anti-reference wins.

```yaml
colors:
  # [fill in — placeholders below are structural only, not a real palette]
  ink: "#000000"           # primary text
  surface: "#FFFFFF"        # page background
  surface-raised: "#F5F5F5" # cards, panels
  border: "#E0E0E0"
  primary: "#000000"        # primary action color — fill in once chosen
  success: "#1E7A4C"
  warning: "#B8720A"
  danger: "#C23A2E"
  agent-draft: "#6B5FE0"    # required: visually marks agent-authored,
                             # unconfirmed content per PRODUCT.md's design
                             # principle — must be distinct from `primary`

typography:
  # [fill in font choices — leave unset rather than defaulting to a generic
  # AI-SaaS pairing; see PRODUCT.md anti-references before picking]
  font-body: "system-ui, sans-serif"
  font-mono: "ui-monospace, monospace"   # for IDs, logs, agent tool output
  scale:
    xs: "12px"
    sm: "14px"
    base: "16px"
    lg: "20px"
    xl: "28px"

spacing:
  scale: [4, 8, 12, 16, 24, 32, 48, 64]   # px — reference by index, not
                                            # arbitrary one-off values

radius:
  sm: "4px"
  md: "8px"
  lg: "12px"

components:
  card:
    background: "{colors.surface-raised}"
    border: "1px solid {colors.border}"
    radius: "{radius.md}"
  agent-approval-prompt:
    # renders the "approval gate" from CLAUDE.md §3 — must be visually
    # distinct from normal chat content, keyboard-operable (see
    # PRODUCT.md accessibility commitments)
    background: "{colors.agent-draft}"
    radius: "{radius.md}"
```

## Notes for `/src/interfaces` implementers

- Reference tokens by name (`{colors.primary}`), don't copy hex values into
  components — when a token changes here, every consumer should update.
- `agent-draft` and `agent-approval-prompt` exist because of a hard
  requirement, not a stylistic choice: PRODUCT.md's design principles and
  CLAUDE.md's human-in-the-loop guardrails both require agent-originated,
  unconfirmed content to be visually unmistakable from confirmed
  human/system content. Don't remove or reuse this token for anything else.

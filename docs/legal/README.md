# Legal templates & compliance checklist (EdgeHub / SKYPhoenix IT)

> ⚠️ **Not legal advice.** These are fill-in templates to hand to a lawyer /
> Steuerberater, not finished documents. German/EU rules change and depend on your
> exact setup (legal form, whether you use a Merchant of Record, etc.). Have them
> reviewed before you publish or charge money. Replace every `[[PLACEHOLDER]]`.

## What a German commercial site selling digital goods needs

| # | Requirement | File | Notes |
|---|---|---|---|
| 1 | **Impressum** (§5 DDG, ex-§5 TMG) | `impressum.md` | Legally required on any business website in Germany. Must be reachable in ≤2 clicks. |
| 2 | **Datenschutzerklärung** (GDPR/DSGVO Art. 13) | `datenschutz.md` | Required whenever you process personal data (checkout, analytics, server logs). |
| 3 | **AGB / Terms + EULA** | `agb.md` | Terms of sale + software licence for the paid build. Optional but strongly advised. |
| 4 | **Widerrufsbelehrung** (right of withdrawal) | `widerruf.md` | EU consumer right for digital goods; include the **explicit waiver** so buyers get instant access and forfeit withdrawal. |
| 5 | **Cookie/consent banner** | - | Only if you set non-essential cookies or load third-party scripts. The current static site sets none; keep it that way and you may not need a banner (still disclose essential/checkout cookies in the privacy policy). |
| 6 | **VAT handling** | see `../LICENSING_STRATEGY.md` §4 | Use a **Merchant of Record** (Paddle / Lemon Squeezy / Gumroad) so VAT is collected/remitted for you and MoR appears on invoices. |

## The single most important shortcut

**Sell through a Merchant of Record.** Paddle / Lemon Squeezy / Gumroad become the
legal seller: they handle EU VAT, invoices, refunds, and even the withdrawal flow.
That shrinks items 3–4–6 above dramatically (their terms cover the transaction; yours
cover the software licence + privacy). You still need the **Impressum** and a
**Datenschutzerklärung** for your own website.

## Placement on the site

The marketing site already links **Impressum · Datenschutz · AGB · Widerruf** in the
footer (currently `#` anchors). Wire each to a real page rendering the finished text.
On a static host, that's four small HTML pages; the content comes from these files.

## Before launch - quick checklist

- [ ] Impressum filled + reachable from every page (footer link) ✅ links exist
- [ ] Datenschutzerklärung filled; matches what you actually collect
- [ ] Chosen payment provider (MoR recommended) + their terms linked at checkout
- [ ] AGB/EULA reviewed by a lawyer; licence terms match the open-core model
- [ ] Widerruf notice + explicit-consent checkbox at checkout for instant download
- [ ] Trademark: "EdgeHub" clear; "Corsair"/"Xeneon Edge" only nominative + disclaimer ✅ on site
- [ ] Test invoices show the correct seller (you or the MoR) + VAT

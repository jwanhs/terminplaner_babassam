# Legal — drafts, and what still blocks a paying customer

**These are drafts, not legal advice.** Nobody here is a lawyer. They exist so
that the conversation with one starts from a document instead of a blank page,
and so the technical annex is written by the people who know what the code
actually does. Every file needs review by a Rechtsanwalt or a
Datenschutzbeauftragter before it goes to a shop.

| File | What it is |
| --- | --- |
| `AVV-Vorlage.md` | Auftragsverarbeitungsvertrag, Art. 28 DSGVO — the contract every business customer needs before they may hand us a single phone number |
| `Anlage-1-TOM.md` | The Art. 32 technical and organisational measures. Written from the code, not from a template |
| `Anlage-2-Unterauftragsverarbeiter.md` | Sub-processors. **Has blanks that must be filled from the real deployment** |
| `Datenschutzerklaerung-Vorlage.md` | Privacy notice for the shop's own booking page |

## Why this is a sales blocker and not paperwork

A salon that takes bookings is the *Verantwortlicher* for its customers' data.
We are the *Auftragsverarbeiter*. Art. 28 (3) DSGVO requires a contract between
them **before** the processing starts. Without it the shop is the one exposed,
and a shop owner whose Steuerberater or Innung asks "habt ihr einen AVV?" will
hear "no" and stop the conversation. An AVV is not a nice-to-have that follows
the first invoice; it is part of the first invoice.

## What must be settled before any of this can be signed

These are open questions about the deployment, not drafting problems. The
documents have `[…]` where the answer belongs.

1. **Hosting — better than assumed, and nearly settled.** Appwrite is
   self-hosted at `write.haey.eu`, not Appwrite Cloud. That removes a processor
   rather than documenting one: nobody at Appwrite holds any customer data, and
   `Anlage 2` names one company on this tier instead of two.

   The server resolves to OVH, a French company, so a third-country transfer
   almost certainly does not arise. **Still to confirm: which datacentre.** OVH
   operates outside the EU too, and "EU" is a claim rather than a fact until
   somebody has looked in the account. Fill it in, then the Datenschutzerklärung
   blank closes with it.

2. **Google Fonts — fixed.** `lib/core/theme.dart` used to call
   `GoogleFonts.playfairDisplay()` and `GoogleFonts.inter()` with no font assets
   bundled, so the package downloaded them from Google on first use and handed
   every visitor's IP address to Google — the fact pattern behind LG München I,
   20.01.2022 (3 O 17493/20).

   Both families are now bundled under `assets/fonts/` with their OFL licences,
   the `google_fonts` dependency is gone, and `test/fonts_test.dart` fails if it
   comes back. There is no runtime fetch left to switch off.

   **CanvasKit — fixed, and confirmed against a real build.** The guard did
   fire on the first real build, on three files. Flutter's loader chooses
   between Google's CDN and a local copy from a flag, so the build now passes
   `--no-web-resources-cdn` (probed, since older toolchains lack it) and
   rewrites the leftover URL so no Google address remains in the artefact.

   **The font fallback needs a decision — read this before selling anything.**
   The same build revealed a second fetch, unrelated to the renderer. When a
   character appears that none of the bundled fonts contain, CanvasKit
   downloads a Noto face for it from `fonts.gstatic.com` — at the moment a
   customer types their name. Nothing configures it, so the default is the live
   value; the build now rewrites it to a path on our own origin.

   Nothing is served at that path yet, so the consequence is that an uncovered
   glyph renders as an empty box instead of reaching Google. For a German
   booking page that is a good trade: the bundled Inter covers Latin including
   German and Turkish. It is the wrong trade for a shop whose customers write
   their names in Arabic or another non-Latin script — and the app already
   lists `ar` among its supported locales.

   Two ways to close it, and it is a product decision rather than a technical
   one: mirror the Noto faces onto the same origin, or leave the boxes and say
   so. **Verify on a real device before either** — that the app still renders
   when a fallback download fails has been reasoned about, not observed.

3. **Nothing deletes old data.** The AVV promises deletion on request and at the
   end of the contract, and `Anlage 1` says retention is bounded. Neither is true
   yet: no sweeper exists, and no retention period has been chosen. Both
   documents mark this. Pick a period (a booking history is useful to a salon,
   so this is a business decision, not only a legal one), then write the job.

4. **`notes` is a free-text field.** 500 characters that staff can type anything
   into, including "Allergie", "Chemo", "schwanger" — Art. 9 special categories,
   which raise the bar on everything. The AVV instructs the shop not to enter
   them. That instruction is worth reinforcing in staff training, and worth
   considering as a hint in the UI.

5. **Blanks to fill.** Company name, address, Vertretungsberechtigter, contact
   for data protection, and the shop's own details. Search for `[` in each file.

## Order of work

The AVV can be signed without reminders existing. The Google transfers under
(2) are closed for the fonts and the renderer, which were the ones that fired
on every page load — those no longer block a signature.

What is left of (2) is the font fallback, and it only fires on a glyph the
bundled fonts do not cover. Decide it before a shop with non-Latin customer
names goes live, not before the first German one does. Then (3), retention,
because the AVV promises a deletion the code does not yet perform — that one is
a promise in a signed contract, which makes it the next thing worth an
afternoon.

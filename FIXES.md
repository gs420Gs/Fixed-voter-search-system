# Fixes Applied

This is the original `bangladesh-voter-python` repo with the following
bugs fixed. Every fix below was verified by actually running the app
(not just reading the code) — see the inline comments at each change
for details.

## 🔴 Critical

1. **Frontend defaulted to the original author's live backend URL.**
   `frontend/src/App.js` used to fall back to
   `https://bangladesh-voter-python.onrender.com/api` whenever
   `REACT_APP_API_URL` wasn't set at build time — so a build that forgot
   to configure it would silently send admin logins and voter data to
   someone else's server instead of failing loudly. Now defaults to
   `localhost` (safe for local dev) and prints a console warning if
   that default is still active once actually deployed.

2. **Hardcoded, publicly-known weak default credentials.**
   `app/auth.py` used to fall back to `ADMIN_PASSWORD="admin123456"`
   and a fixed placeholder `JWT_SECRET` whenever those env vars weren't
   set. Since the repo is public on GitHub, those defaults were visible
   to anyone. Now: if the env var is missing, a strong random value is
   generated for that process only, and a warning is logged telling you
   to set it explicitly before any real/shared deployment.

3. **`render.yaml` wired the app to Render's free Postgres, which is
   unworkable at real voter-list scale.** Render's free Postgres plan is
   capped at **1 GB storage** and **expires 30 days after creation**
   (14-day grace period to upgrade, then it's deleted). Switched the
   default `DATABASE_URL` to SQLite, which has no such cap or expiry.

4. **Every uploaded PDF was stored twice** — once on disk
   (`stored_path`) and again as a full binary BLOB in the `pdf_data`
   database column. Harmless for a handful of files; at tens-of-GB
   scale it silently doubles storage needs and is the fastest way to
   fill up a database. Uploads now only write to disk; the `pdf_data`
   column is kept in the schema (so old rows still work) but is no
   longer written to.

## 🟡 Correctness / maintainability

5. **Three different `process_pdf()` implementations, two of them dead
   code.** `processing.py`, `pdf_font_decoder.py`, and
   `font_processing.py` each had their own `process_pdf()`. Only
   `font_processing.process_pdf()` was ever actually called (via
   `api.py`). The other two were unreachable — editing them to fix a
   bug would silently do nothing. Removed both dead implementations;
   kept the helper functions other modules still import
   (`native_records`, `repair`, `normalize_field`, etc.).

6. **`app/jobs.py` was entirely dead code.** It defined
   `process_document()`, which was never imported or called anywhere
   (`api.py` has its own inline `_run_document()` that does the real
   work). It also called yet another, different extraction path.
   Deleted the file.

7. **Invalid regex escape sequences.** Several field-label patterns in
   `processing.py` used plain `"...\s..."` strings instead of raw
   `r"...\s..."` strings, which triggers a `SyntaxWarning` in current
   Python and would become a hard error in a future Python version.
   Fixed by adding the `r` prefix.

8. **Hardcoded GitHub Pages subpath in the frontend.**
   `const BASE = '/bangladesh-voter-python'` meant forking or renaming
   the repo (or deploying anywhere other than that exact path) produced
   a blank page. Now defaults to the site root (works for
   Render/Netlify/Vercel out of the box) and is overridable via
   `REACT_APP_BASE_PATH` for GitHub Pages project-subpath deployments.

9. **No `.gitignore`.** The repo had no `.gitignore` at all, risking
   accidental commits of the local SQLite DB, uploaded PDFs, or `.env`
   files (i.e. real personal voter data or secrets ending up in git
   history). Added one.

## 🔴 Critical -- found by testing against a real voter-list PDF

10. **Every successful native-font extraction crashed before saving to the
    database.** `font_processing.py` tags each extracted record with an
    `"extraction_method"` key (e.g. `"native-font"`), but the `VoterRecord`
    database model has no such column. `api.py` already popped the similar
    `"ocr_used"` key for the same reason but missed this one, so
    `VoterRecord(**r)` raised `'extraction_method' is an invalid keyword
    argument for VoterRecord` on every single record. The document was
    marked `"failed"` even though extraction itself had fully succeeded --
    **zero records were ever persisted, silently**, for any real
    (non-scanned) voter-list PDF. This is the main code path, so this bug
    made the core upload feature non-functional. Verified against a real
    492-record voter list PDF: before the fix, 0/492 records saved; after,
    492/492 saved and searchable.

11. **District metadata failed to extract on this PDF's cover page.** The
    label "জেলা" (district) sometimes loses its vowel sign during font
    decoding, extracting as "জলা". The original regex only matched the
    fully-correct spelling, so `district` was `None` for every record.
    Made the vowel optional, anchored to line-start so it can't also match
    the "জলা" substring inside "উপজেলা" (upazila) -- verified against the
    real extracted text before shipping. Verified: `top_districts` in
    `/api/voter-search/stats` now correctly reports the district instead
    of an empty list.

## Known limitations found during real-PDF testing (not fixed -- see why)

- **A small number of names (~1% in the test PDF) have one misplaced
  vowel sign mid-word** (e.g. "সিদ্দিক" may extract as "সিিদ্দক"). The
  underlying vowel-sign reordering logic is not idempotent and is
  applied multiple times across different call sites (page-level,
  then again per extracted field); two different attempts at fixing
  the mid-word case were tested against the real 492-record PDF and
  both introduced *new*, more frequent corruption elsewhere in the
  same document (e.g. correctly-spelled "পিতা" becoming "পতিা") --
  because a "consonant + vowel-sign" pattern looks identical whether
  it's already correct or still corrupted; there's no reliable way to
  tell them apart from the character sequence alone. Both attempts
  were reverted rather than ship a fix that trades a small number of
  visibly-wrong names for a larger, harder-to-notice one. Voter ID,
  father's name, mother's name, address, occupation, and birth date
  are unaffected and were spot-checked against the source document.
- **`union_name` and `ward` don't extract from this PDF's cover page.**
  Unlike `district`/`upazila` (single line, `label: value`), the
  cover page's union/ward section spans multiple lines with the label
  and value on separate lines, plus an unmapped glyph (a raw control
  byte) in the middle of the "ক্যান্টনমেন্ট" label. Fixing this
  properly needs the multi-line cover-page layout to be parsed
  generally (not just pattern-matched), which is a larger, riskier
  change than the scope of this fix pass -- left as a known gap
  rather than a rushed, unverified patch. Per-record data (name,
  father, mother, voter ID, address, occupation, birth date,
  district, upazila) is unaffected.

## What was already good (kept as-is)

- JWT auth + `admin_user` dependency protecting every data endpoint —
  matches a private/personal-use deployment, not a public site.
- The font-aware Bengali glyph decoder (`pdf_font_decoder.py`) that
  reverse-engineers the embedded font used in real Bangladesh Election
  Commission voter PDFs — genuinely well done, more reliable than
  falling back to OCR for text-based pages.
- The automatic quality-scoring layer (`quality.py`) that flags
  suspicious records for review without guessing/rewriting names.

## Known limitation not fixed here (by design)

No single free-tier database (SQLite included) makes ~29 GB / ~12 crore
national voter records instantly searchable online for $0 with no
card and no local machine involved — that's a real storage-capacity
limit, not a bug in this code. See the deployment conversation for
the realistic options (processing locally once and hosting only the
smaller extracted dataset, sharding by district across multiple free
databases, or a modest paid VPS).

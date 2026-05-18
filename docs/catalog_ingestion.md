# Catalog and Legal Text Ingestion

## Goodreads Catalog

Build the diploma catalog seed from the ALS 20k recommendation universe, then
fill missing language coverage from Goodreads metadata:

```bash
.venv/bin/python scripts/build_goodreads_catalog_seed.py \
  --output-csv goodreads_catalog_seed_20k.csv
```

For an existing Postgres database, run the one-time schema guard before import:

```bash
psql postgresql://postgres:12345@localhost:5432/ebookreader \
  -f scripts/migrate_catalog_schema.sql
```

Then import:

```bash
.venv/bin/python goodreads_import.py \
  --books-csv goodreads_catalog_seed_20k.csv \
  --output-csv goodreads_catalog_seed_20k.csv \
  --min-ratings 0 \
  --max-books 20000 \
  --db-import
```

The supported diploma language set is `eng`, `spa`, `ara`, `por`, `rus`, and
`kaz`. Goodreads remains metadata-only unless a legal text source is imported.

## EPUB Chapters

Create a manifest for public-domain, open-license, or admin-owned EPUB files:

```csv
goodreads_id,epub_path,source_type,source_name,license
1885,/absolute/path/pride-and-prejudice.epub,PUBLIC_DOMAIN_EPUB,Project Gutenberg,Public domain
```

Preview chapter extraction:

```bash
.venv/bin/python scripts/import_epub_content.py --manifest legal_epubs.csv --dry-run
```

Import chapters:

```bash
.venv/bin/python scripts/import_epub_content.py --manifest legal_epubs.csv
```

The importer creates `book_content_bundles`, replaces existing chapters for the
book, stores full chapter text, and marks the book as `TEXT` or `SYNCED`.

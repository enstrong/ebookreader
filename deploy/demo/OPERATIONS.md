# eBookReader public demo

The deployment runs Flutter web, Spring Boot, PostgreSQL, the existing trained hybrid ALS model, and LibreTranslate on one OCI VM. Visitors only open the HTTPS URL. Infrastructure commands below are for the owner, never visitors.

The `demo` Spring profile disables registration, admin tools, and GraphQL. A browser automatically receives a separate authenticated visitor account, valid for 24 hours. Progress, ratings, notes, reviews, and uploaded originals/chapters live in PostgreSQL. Cleanup runs every 15 minutes; reset deletes the current visitor immediately. Shared catalog books and the model are retained. Uploads accept unencrypted EPUB, FB2, and UTF-8 TXT: 10 files, 10 MB per file, 8 MB expanded content, and 20 MB total per account. Capacity is limited to approximately 100 simultaneous sessions, with proxy rate limits.

## Build and deploy

1. Keep the existing trained inference artifacts outside Git: `als_model.pkl`, `mappings.pkl`, and `metadata.json` in `data/recommendations/experiments/als_reads_workcanon_20k_f256_i2_lam1p0_validation_split/`; the metadata CSV and work map in `data/recommendations/hybrid/`. Never substitute a mock recommender. Training data and the user-items training matrix are unnecessary for inference.
2. Run `python3 deploy/demo/prepare_catalog.py`. The optional existing `data/goodreads/goodreads_book_authors.json.gz` supplies display names. This generates `build/demo/catalog.json` from the same 20k book universe as the model.
3. Run `mvn -f backend/pom.xml test package` and `FLUTTER=/path/to/flutter deploy/demo/build_web.sh`. The web build uses a clean temporary directory and never includes the native app's `.env` secrets.
4. Copy `deploy/demo/`, `build/web/`, `build/demo/catalog.json`, the backend JAR, `backend/assets/`, recommender scripts, and the inference artifacts to the server, preserving relative paths. Do not upload the development PostgreSQL directory.
5. On the server, create `deploy/demo/.env` from `.env.example`, generate independent random database/JWT secrets, set permissions `600`, and set `DEMO_HOST` to the chosen hostname. Do not commit this file.
6. Run `docker compose --project-directory deploy/demo -f deploy/demo/compose.yml up -d --build`. Only Caddy publishes ports 80/443; the database, model, and translator are private. Port 18888 binds to localhost for maintenance. Permit TCP 80/443 in the OCI security list and guest firewall. Caddy obtains and renews HTTPS certificates.
7. Run `python3 deploy/demo/smoke_test.py https://YOUR-HOST`. It creates disposable accounts and tests real database writes, account isolation, three upload formats, the actual model, translation, audio ranges, and revocation. It cleans up its own accounts.

After replacing the JAR, recreate the backend container so its file mount uses the new inode: `docker compose -f deploy/demo/compose.yml up -d --force-recreate backend`. After changing nginx/Caddy configuration, reload or recreate the respective service. Static web files update in place.

## Operations and cost

The configured VM is Always Free A1 with 2 OCPUs, 12 GB memory, and one approximately 50 GB boot volume. The account remains Free Tier; no paid account upgrade, paid database, domain purchase, or subscription is needed. Monitor the OCI console before changing resource sizes or adding resources. Oracle's free capacity and idle-instance policies still apply; free hosting is not an uptime guarantee.

PostgreSQL and translation models use named Docker volumes. Caddy's certificate state also persists in a volume. Keep the SSH key and `.env` outside Git. Never run `docker compose down -v` unless intentionally deleting all demo data. Redeploying to a different IP requires updating the hostname and `DEMO_HOST`. The sslip.io hostname depends on the current public IP and is not a purchased domain.

Complete text samples are from Project Gutenberg (ebooks 11 and 1342), with source notices/licenses retained in the files. The existing Raven/LibriVox asset is reused. Goodreads metadata supplies recommendation candidates; most catalog candidates are metadata only, while the seeded public-domain books and private uploads are readable.

Browser QA covers desktop and a 390 × 844 responsive browser viewport; this does not substitute for a physical iOS/Android device test. The repository's old default Flutter counter widget test still expects a counter UI that this app does not have; the model/auth Flutter tests and backend tests are separate from that obsolete fixture.

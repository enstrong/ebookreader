# Recommendation Engine Notes

This project starts without a GUI. For now, the recommendation engine is a set
of terminal-run data scripts. That is a good shape for learning because each
stage has one job and visible inputs/outputs.

## Phase 4 Data Preparation

The UCSD Goodreads interaction CSV is large, so we process it in chunks instead
of loading it all into memory.

The first preparation script is:

```bash
.venv/bin/python scripts/recommendations/prepare_goodreads_interactions.py --help
```

To download the full interaction CSV and the two ID maps:

```bash
.venv/bin/python scripts/recommendations/prepare_goodreads_interactions.py --download
```

To run a small learning-sized test on the first 1,000,000 rows:

```bash
.venv/bin/python scripts/recommendations/prepare_goodreads_interactions.py \
  --filter \
  --max-rows 1000000 \
  --output data/recommendations/interactions_filtered_sample.csv \
  --summary data/recommendations/interactions_filtered_sample.summary.json
```

To filter the full downloaded CSV:

```bash
.venv/bin/python scripts/recommendations/prepare_goodreads_interactions.py --filter
```

## What The Filter Does

The script makes two passes over the interactions.

Pass 1 counts only rows where `rating > 0`. These are explicit ratings, not just
read/unread shelf activity.

Pass 2 keeps only rows where:

- `rating > 0`
- the user has at least `--min-user-ratings` rated books
- the book has at least `--min-book-ratings` ratings

This gives us a denser user-book matrix. Dense does not mean full. It means the
remaining users and books have enough overlap to make collaborative filtering
less random.

## Why The Book Map Matters

The interaction CSV uses compact UCSD CSV IDs. `book_id_map.csv` maps those IDs
back to Goodreads book IDs. The filtered output keeps both:

- `book_id`: UCSD's compact interaction ID
- `goodreads_book_id`: the real Goodreads book ID, useful for joining to book
  metadata or to this app's `books.goodreads_id`

## Level 2: Item-Item Collaborative Filtering

Level 2 is still "memory-based." There is no trained neural network or matrix
factorization model. The system directly remembers patterns from the data.

The first Level 2 script is:

```bash
.venv/bin/python scripts/recommendations/build_item_cf.py --help
```

For a fast prototype, build similarities from the sample filtered file:

```bash
.venv/bin/python scripts/recommendations/build_item_cf.py \
  --interactions data/recommendations/interactions_filtered_sample.csv \
  --output data/recommendations/item_cf_similar_sample.csv \
  --metadata data/recommendations/item_cf_metadata_sample.json \
  --top-books 1000 \
  --neighbors-per-book 20 \
  --min-co-likes 3
```

For a larger run on the full filtered file:

```bash
.venv/bin/python scripts/recommendations/build_item_cf.py \
  --interactions data/recommendations/interactions_filtered.csv \
  --output data/recommendations/item_cf_similar.csv \
  --metadata data/recommendations/item_cf_metadata.json \
  --top-books 5000 \
  --neighbors-per-book 25 \
  --min-co-likes 5
```

Then query a known Goodreads book ID:

```bash
.venv/bin/python scripts/recommendations/query_item_cf.py \
  --similarities data/recommendations/item_cf_similar_sample.csv \
  --goodreads-book-id 21
```

To recommend from a few manually supplied liked books:

```bash
.venv/bin/python scripts/recommendations/recommend_item_cf.py \
  --similarities data/recommendations/item_cf_similar.csv \
  --liked-goodreads-book-id 21:5 \
  --liked-goodreads-book-id 43615:4
```

To recommend for a known UCSD dataset user:

```bash
.venv/bin/python scripts/recommendations/recommend_item_cf.py \
  --similarities data/recommendations/item_cf_similar.csv \
  --interactions data/recommendations/interactions_filtered.csv \
  --user-id 0
```

### How The Level 2 Score Works

We first convert ratings into likes. By default, `rating >= 4` means "liked."

For each user, we look at the candidate books they liked. If a user liked both
Book A and Book B, that adds one `co_like` to the pair.

The basic similarity score is cosine similarity over binary liked/not-liked
vectors:

```text
similarity(A, B) = co_likes(A, B) / sqrt(likes(A) * likes(B))
```

This rewards books liked by the same people, while reducing the advantage that
very popular books get just from being everywhere.

The script also applies significance weighting:

```text
score = cosine_similarity * min(co_likes / 50, 1)
```

This keeps a pair with only 2 shared fans from looking magically perfect.

### From Similar Books To Recommendations

Similarity answers: "what is close to this one book?"

Recommendation answers: "given all the books this user liked, what unread books
collect the most neighbor evidence?"

The recommendation script does this:

- find the user's liked books, where `rating >= 4`
- get similar books for each liked book
- multiply each similarity by a small rating weight
- sum scores for repeated candidates
- remove anything the user already read

## Backend Interaction Memory

The Goodreads interaction dataset gives the system broad crowd behavior. The
app still needs its own per-user memory so recommendations can change after a
real app user reads or rates a book.

The backend stores that memory in `UserBook`. In addition to bookmark/progress,
it now tracks:

- `status`: `WANT_TO_READ`, `READING`, `FINISHED`, or `DNF`
- `rating`: nullable 1-5 rating
- `startedAt`
- `finishedAt`
- `lastReadAt`

The app can update that memory with:

```text
PUT  /api/user/books/{bookId}/status
POST /api/user/books/{bookId}/finish
PUT  /api/user/books/{bookId}/rating
```

The recommendation endpoint is:

```text
GET /api/recommendations/me
```

It works like this:

1. Load the current app user's `UserBook` rows.
2. Convert useful interactions into source weights:
   - rating 5: strong positive signal
   - rating 4: positive signal
   - finished without rating: moderate signal
   - currently reading: weaker signal
   - bookmarked: light signal
3. Map the app's `Book.goodreadsId` values into the Level 2 item similarity
   artifact.
4. Sum neighbor scores and filter out books the user already touched.
5. Return app `Book` records with recommendation scores.

This means the offline model does not need to retrain after every book. A new
rating changes the user's source weights, so the next recommendation request can
change immediately.

## Evaluating Level 2

Eyeballing recommendations is useful, but evaluation is how we know whether one
model is better than another.

The first evaluation script uses a leave-one-out test:

```bash
.venv/bin/python scripts/recommendations/evaluate_item_cf.py \
  --interactions data/recommendations/interactions_filtered.csv \
  --similarities data/recommendations/item_cf_similar.csv \
  --max-users 10000
```

For each user, it:

1. finds books they liked
2. hides one liked book
3. recommends from the remaining liked books
4. checks whether the hidden book appears in the top K

The main metrics are:

- `HitRate@K`: how often the hidden book appeared in the top K
- `MRR`: mean reciprocal rank, which rewards finding the hidden book near the
  top of the list

This lets us compare Level 2 against future ALS/matrix-factorization models.

## Improving Level 2

Improvement should be experimental, not vibes-based. Keep one baseline, change
one thing, evaluate again, then compare.

Run the Level 2 experiment harness:

```bash
.venv/bin/python scripts/recommendations/run_item_cf_experiments.py \
  --max-users 10000
```

The first two variants are:

- `baseline_rating4_top5000`: ratings 4-5 count as liked
- `strict_rating5_top5000`: only rating 5 counts as liked

This tests a real hypothesis:

```text
Does a stricter "like" signal improve recommendation quality, or does it throw
away too much useful data?
```

## Level 3: Matrix Factorization With ALS

Matrix factorization learns two matrices:

- `user_factors`: one latent taste vector per user
- `item_factors`: one latent feature vector per book

The first ALS trainer uses the `implicit` Python library:

```bash
.venv/bin/python scripts/recommendations/train_als.py \
  --interactions data/recommendations/interactions_filtered_sample.csv \
  --output-dir data/recommendations/als_sample \
  --top-books 1000 \
  --factors 32 \
  --iterations 5
```

After training, inspect the metadata:

```bash
cat data/recommendations/als_sample/metadata.json
```

Query user recommendations:

```bash
.venv/bin/python scripts/recommendations/query_als.py \
  --model-dir data/recommendations/als_sample \
  --user-id 0
```

Query similar books:

```bash
.venv/bin/python scripts/recommendations/query_als.py \
  --model-dir data/recommendations/als_sample \
  --similar-goodreads-book-id 21
```

This ALS model treats ratings as implicit positive feedback. A 5-star rating is
not interpreted as "predict exactly 5 stars"; it is interpreted as strong
evidence that the user likes that book.

### Mean-Centered ALS

The first ALS run was too sparse because it used only 5-star ratings. The denser
version uses all explicit ratings and converts them into relative preference:

```text
centered_rating = rating - user's_average_rating
```

That changes the meaning of a rating:

- a 3-star rating from a user who usually gives 1-2 stars can be positive
- a 3-star rating from a user who usually gives 4-5 stars can be negative

The `implicit` library accepts negative matrix entries as disliked items with
confidence, so the trainer stores signed confidence values:

```text
positive value = above this user's norm
negative value = below this user's norm
magnitude      = how confident the signal is
```

Train the 20k-book mean-centered model:

```bash
.venv/bin/python scripts/recommendations/train_als.py \
  --interactions data/recommendations/interactions_filtered.csv \
  --output-dir data/recommendations/als_mean_centered_20k \
  --signal-mode mean-centered \
  --top-books 20000 \
  --factors 64 \
  --iterations 20 \
  --min-user-likes 5
```

The first full run produced:

```text
user_factors: (647037, 64)
item_factors: (20000, 64)
training signals: 59,527,078
positive signals: 34,468,779
negative signals: 24,897,258
```

Evaluate ALS using the same 5-star holdout style as Level 2:

```bash
.venv/bin/python scripts/recommendations/evaluate_als_holdout.py \
  --model-dir data/recommendations/als_mean_centered_20k \
  --allowed-similarities data/recommendations/experiments/strict_rating5_top5000.similar.csv \
  --output data/recommendations/als_mean_centered_20k/evaluation_holdout_level2_5k.json
```

That restricted comparison keeps the candidate universe at the same 5,000 books
used by the best Level 2 model. It is the cleanest apples-to-apples comparison.

The unrestricted 20k evaluation is harder because the model must rank the hidden
book among 20,000 candidates instead of 5,000:

```bash
.venv/bin/python scripts/recommendations/evaluate_als_holdout.py \
  --model-dir data/recommendations/als_mean_centered_20k \
  --output data/recommendations/als_mean_centered_20k/evaluation_holdout_20k.json
```

### Read-Unrated Signals

The Goodreads interactions include rows where `rating == 0` and `is_read == 1`.
Those rows mean the user read the book but did not rate it. In the
Hu/Koren/Volinsky implicit-feedback framing, that is still a weak preference
signal:

```text
preference = 1
confidence = 1
```

This is weaker than an explicit above-average rating, but it is better than
pretending the user never touched the book.

Prepare a read-aware interaction file:

```bash
.venv/bin/python scripts/recommendations/prepare_goodreads_interactions.py \
  --filter \
  --include-read-unrated \
  --output data/recommendations/interactions_with_reads.csv \
  --summary data/recommendations/interactions_with_reads.summary.json
```

Train the read-aware 20k model:

```bash
.venv/bin/python scripts/recommendations/train_als.py \
  --interactions data/recommendations/interactions_with_reads.csv \
  --output-dir data/recommendations/als_reads_20k \
  --signal-mode mean-centered \
  --top-books 20000 \
  --factors 64 \
  --iterations 20 \
  --min-user-likes 5 \
  --mean-shrinkage 5
```

This run produced:

```text
user_factors: (685033, 64)
item_factors: (20000, 64)
training signals: 63,236,217
explicit positive signals: 34,908,237
explicit negative signals: 24,993,120
weak read-unrated signals: 3,334,860
```

The 20k explicit 5-star holdout improved over the prior mean-centered 20k model:

```text
previous ALS:   Hit@5 16.11%, Hit@10 21.36%, Hit@20 27.58%, Hit@50 38.80%
read-aware ALS: Hit@5 17.23%, Hit@10 22.56%, Hit@20 29.66%, Hit@50 40.18%
```

The same model restricted to the Level 2 5k universe scored:

```text
Hit@5 22.02%, Hit@10 29.05%, Hit@20 37.57%, Hit@50 51.32%, MRR 0.1621
```

## Level 3B: NumPy ALS From Scratch

The NumPy version is for learning the math directly. It does not use the
`implicit` library for training. The core update is our own call to:

```python
np.linalg.solve(a_matrix, b_vector)
```

Run the sample NumPy model:

```bash
.venv/bin/python scripts/recommendations/train_als_numpy.py \
  --interactions data/recommendations/interactions_filtered_sample.csv \
  --output-dir data/recommendations/als_numpy_sample \
  --top-books 1000 \
  --factors 32 \
  --iterations 5 \
  --min-user-likes 3
```

Query it:

```bash
.venv/bin/python scripts/recommendations/query_als_numpy.py \
  --model-dir data/recommendations/als_numpy_sample \
  --similar-goodreads-book-id 1885
```

Evaluate it:

```bash
.venv/bin/python scripts/recommendations/evaluate_als_numpy_holdout.py \
  --model-dir data/recommendations/als_numpy_sample \
  --interactions data/recommendations/interactions_filtered_sample.csv \
  --output data/recommendations/als_numpy_sample/evaluation.json
```

The line-by-line walkthrough is in:

```text
docs/numpy_als_walkthrough.md
```

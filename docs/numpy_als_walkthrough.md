# NumPy ALS Walkthrough

This document explains the from-scratch ALS trainer in
`scripts/recommendations/train_als_numpy.py`.

The important promise: the script does not call `implicit`. It uses NumPy for
the factorization math and `np.linalg.solve` for the linear systems.

## What We Are Optimizing

For every user `u` and book `i`, ALS tries to make this dot product high when
the user liked the book:

```text
prediction(u, i) = user_factors[u] dot item_factors[i]
```

Because this is implicit-feedback ALS, the model does not predict exact stars.
It predicts preference strength. We use mean-centered ratings to decide the
preference:

```text
centered = rating - user_average_rating
preference = 1 if centered > 0 else 0
confidence = 1 + alpha * abs(centered) / centered_scale
```

So:

- above the user's norm: positive preference
- below the user's norm: negative evidence
- farther from the norm: higher confidence

The ALS update for one user is:

```text
A = Y.T Y + Y_observed.T (C - I) Y_observed + lambda I
b = Y_observed.T (C * p)
x = solve(A, b)
```

Where:

- `Y` is the item-factor matrix
- `Y_observed` is only the books this user rated
- `C` is confidence for those ratings
- `p` is preference, 1 for positive and 0 for negative
- `x` is the new vector for this user

Then we do the same thing in reverse to solve every book vector while user
vectors are fixed.

## Line-By-Line Map

### Setup

- Lines 1-6: declare this as an executable Python script and describe its job.
- Lines 8-18: import standard Python helpers, NumPy, and pandas. Pandas is only
  for chunked CSV reading; NumPy does the ALS math.
- Line 21: defines the only columns we need from the interactions CSV.

### Reading Data

- Lines 24-26: `read_chunks` streams the CSV instead of loading all rows into
  memory. The dtypes keep memory smaller.
- Lines 29-31: `update_counter` merges pandas value counts into a normal Python
  `Counter`.

### Pass 1: Book Counts And User Means

- Lines 34-38: define the first scan over the interactions file.
- Lines 39-42: create counters for book popularity and per-user rating totals.
- Lines 44-49: read one chunk and optionally stop at `--max-rows`.
- Line 51: count how many rows we have scanned.
- Line 52: count how often each book appears. This lets us choose top books.
- Line 54: group the chunk by user and compute rating sum plus rating count.
- Lines 55-57: add those chunk-level sums/counts into global user totals.
- Lines 59-63: print progress so a long dataset run is visible.
- Lines 65-68: compute `user_average_rating = total_rating / rating_count`.
- Lines 69-71: add stats and return book counts, user means, and metadata.

### Pass 2: Mean-Centered Signals

- Lines 74-84: define the second scan over the interactions file.
- Lines 85-87: prepare chunk storage, positive-count tracking, and stats.
- Lines 89-96: read a chunk and respect `--max-rows`.
- Line 97: keep only books in the selected candidate set.
- Line 98: look up each row's user average.
- Line 99: convert ratings to a NumPy float array.
- Line 100: subtract the user's average rating from each rating.
- Line 101: discard exactly neutral rows, or tiny rows if configured.
- Lines 103-104: apply that filter to the rows and centered values.
- Line 105: convert distance from user average into confidence.
- Line 106: convert sign into preference: `True` means positive.
- Lines 108-109: store confidence and preference back into the dataframe.
- Line 110: update how many candidate signals we found.
- Lines 112-113: count positive signals per user.
- Line 114: keep this processed chunk for later concatenation.
- Lines 116-120: print progress.
- Lines 122-123: fail clearly if the filters removed everything.
- Line 125: combine processed chunks into one dataframe.
- Lines 126-130: keep only users with enough positive evidence.
- Line 131: filter the dataframe to active users.
- Lines 132-136: record stats and return the training signals.

### Mapping IDs To Matrix Indices

- Lines 139-141: collect sorted user IDs and book IDs.
- Lines 143-145: build mappings between real IDs and zero-based matrix rows.
- Lines 147-150: turn dataframe columns into NumPy arrays.
- Lines 152-159: package mappings so query/evaluation scripts can translate
  back to Goodreads IDs.

### Building CSR-Style Rows

- Lines 162-168: define a compact row structure like CSR sparse matrices.
- Line 169: sort by row first, then column.
- Lines 170-173: reorder columns, confidences, and preferences the same way.
- Line 175: count how many entries each row has.
- Line 176: build `indptr`, where row `r` lives between
  `indptr[r]` and `indptr[r + 1]`.
- Line 177: return arrays that let us quickly fetch one user's or one book's
  observed interactions.

### The ALS Math

- Lines 180-187: define the function that solves all rows on one side.
  It is used once for users and once for books.
- Line 188: compute how many rows we need to solve.
- Line 189: read the number of latent factors.
- Line 190: compute `Y.T @ Y`, the shared part of every linear system.
- Line 191: create the identity matrix for regularization.
- Line 192: allocate the output matrix.
- Line 194: loop over users or books.
- Lines 195-196: find the slice of observed interactions for this row.
- Lines 197-198: if a row has no data, leave its vector as zeros.
- Line 200: get the related item IDs for a user, or related user IDs for a
  book.
- Line 201: pull the fixed vectors for those related rows.
- Lines 202-203: pull confidence and preference values for those interactions.
- Line 205: build the `(C - I)` weighted factor term.
- Line 206: build the left-hand matrix `A`.
- Line 207: build the right-hand vector `b`.
- Line 208: solve `A x = b`; this is the actual ALS update.
- Line 210: return the solved factor matrix.

### Alternating Between Users And Books

- Lines 213-228: define the training loop inputs.
- Line 229: create a reproducible random-number generator.
- Line 230: initialize user vectors as zeros.
- Line 231: initialize item vectors as small random values.
- Line 233: repeat ALS for the configured number of iterations.
- Line 234: start a timer for progress output.
- Lines 235-242: solve all user vectors while item vectors are fixed.
- Lines 243-250: solve all item vectors while user vectors are fixed.
- Lines 251-252: print iteration time.
- Line 254: return the learned matrices.

### Saving

- Lines 257-273: save the compressed row arrays to `.npz`.
- Lines 276-291: define command-line arguments.
- Lines 294-319: run pass 1 and pass 2.
- Lines 321-338: build user-side and item-side compressed rows.
- Lines 340-344: print the matrix size.
- Lines 346-355: train the NumPy ALS model.
- Lines 357-368: save factor matrices, mappings, and row artifacts.
- Lines 370-397: save metadata.
- Lines 399-402: print saved artifact paths.
- Lines 405-406: run `main()` when the file is executed directly.

## Sample Result

The sample command:

```bash
.venv/bin/python scripts/recommendations/train_als_numpy.py \
  --interactions data/recommendations/interactions_filtered_sample.csv \
  --output-dir data/recommendations/als_numpy_sample \
  --top-books 1000 \
  --factors 32 \
  --iterations 5 \
  --min-user-likes 3
```

Produced:

```text
users: 1,834
items: 1,000
signals: 107,119
positive signals: 61,535
negative signals: 45,584
```

The NumPy model and the `implicit` model are not bit-identical because their
initialization and internal numerical details differ, but the sample metrics are
very close:

```text
NumPy ALS sample:    Hit@5 28.8%, Hit@10 39.1%, Hit@20 53.1%, Hit@50 70.6%
implicit ALS sample: Hit@5 29.5%, Hit@10 40.0%, Hit@20 53.6%, Hit@50 70.9%
```

That tells us the from-scratch math is behaving like the library version on the
same mean-centered data.

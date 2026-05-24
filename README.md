#  eBookReader

A cross-platform book app built with Flutter, Spring Boot, and PostgreSQL.
This diploma project is a joint app created with my partner over several months; now I’m continuing it solo.

## What this app does

- Upload books as files from the app, including EPUB and other supported formats.
- Store uploaded book metadata, covers, and content in a backend service.
- Read books on mobile and desktop with a polished Flutter interface.
- Manage books, login/auth, and basic library organization.
- Keep local state and user preferences with `shared_preferences`.
- Get personalized book recommendations from a hybrid recommendation system.
- Rate books and inspect the user's rating history.
- Highlight text, save notes, look up dictionary definitions, and translate selected passages inside the reader.
- Listen to the public-domain demo audiobook and move between text and audio with saved progress.
- Switch between multiple visual themes.

## Core features

### Book upload

- Upload books using the file picker UI.
- EPUB is supported, and the app is designed to accept other book formats if they are allowed by the parser.
- Uploaded books are stored in the backend and become available in the app library.

### Library experience

- Browse and search your books.
- View book details, cover art, and metadata.
- Use the app as a personal reading manager.
- See a visible demo audiobook entry point even when the library is empty.
- Check rated books, star values, and rating dates from the user page.

### Reading experience

- Read imported books inside the app.
- Highlight words or passages and attach notes.
- Look up English and Russian dictionary definitions from selected text.
- Translate selected English words or passages into Russian through LibreTranslate.
- Save looked-up words as vocabulary-style annotations.
- Switch the reader between different app themes.

### Audiobooks and sync

- Open the seeded public-domain demo audiobook, The Raven.
- Use a focused audio player with play/pause, seek, segment navigation, and speed control.
- Save audiobook progress and resume later.
- Continue from reading to listening, or from listening back to the matching text segment.

### Recommendations and ratings

- Generate personalized recommendations from reading and rating signals.
- Use a Python recommendation service for hybrid model logic.
- Store and display rated books so recommendation behavior can be inspected per user.

### Authentication

- Login and user management are handled by the backend service.
- Secure sessions and profile-based library support.
- Google OAuth supports login and registration.

### Backend / infrastructure

- Backend service lives in `backend/` and is built with Java/Spring Boot.
- Uses PostgreSQL for data storage.
- Docker support is included for local backend environment setup.

## Project status

- Work began as a team project and continued across a few months.
- I’m not in a rush to add everything immediately. Today is **April 15th**, and the diploma defense is scheduled for **June 22nd-28th.**

## Future direction (as of April 15th)

This project is headed toward becoming a true book superapp.
The priorities are:

1. **AI Recommendation Engine** -- done by May 16th
   - Add an AI recommendation engine that suggests books based on reading history
   - If a user has no history yet, ask them about books they love or let AI ask a few warm-up questions
   - Add an AI button on the main page to recommend titles dynamically

2. **Reading experience** -- done by May 21st
   - Bookmarks inside books
   - Notes/highlights
   - Highlight words and get definitions
   - Translate words or passages from open-source dictionaries

3. **Audiobooks and sync** -- done by May 21st
   - Support audiobooks and ebook playback together
   - Sync audio position with text so users can listen while walking and continue reading at home

4. **Reviews, ratings, and quotes last** -- in progress
   - Add book reviews and rating pages
   - Add quotes in the far future once core reading and AI functionality are strong

## Tech stack

- Flutter frontend
- Spring Boot backend
- PostgreSQL database
- Docker-compatible backend setup
- Python recommendation service for model training and serving
- Recommendation model tooling with `implicit`, `numpy`, `pandas`, and `scipy`
- LibreTranslate-compatible translation service
- File upload via Flutter `file_picker`
- EPUB parsing and book asset handling via Dart packages

## Author

- Project started with a partner, developed together for 2 months (October and February).
- Partner, that absolutely deserves a lot of credit - [Shonkurieta](https://github.com/Shonkurieta). Frontend developer of this project and also added the EPUB support.
- Now continuing as a solo developer. Also have an internship, part-time job, and I'm training for a half-marathon.
- Main focus: achieve the first 3 of 4 goals at least, which should suffice for a great grade (no pun intended), or even achieve all 4 if I manage my time the best way possible. Though it all depends on how hard Machine Learning is, and I currently have zero idea due to having zero past experience.


---

# Updates
## May 15th, 2026

This was an incredible experience. For the AI recommendation engine, I started small, because I did not want to just run a library and pretend that I understand Machine Learning. The goal was to learn the recommendation problem step by step: first popularity, then similar users/books, and only after that matrix factorization.

The recommendation engine is still backend-only for now. There is no GUI yet, and that is intentional. At this stage it works through scripts, data artifacts, and evaluation files. Basically, terminal first, product UI later.

### Terms I had to define first

Before the models make sense, the metrics and model words have to make sense.

**Interaction** means one user-book event from the Goodreads dataset. In this dataset, an interaction can mean the user read the book, rated it, reviewed it, or some combination of those things.

**Rating** means the explicit 1-5 star score. A rating of `5` is the strongest positive signal. A rating of `4` is also positive, but weaker. Ratings below the user's normal rating average can become negative signals in mean-centered ALS.

**Rating 0** does not mean "zero stars". This is very important. In the UCSD Goodreads interactions file, rating `0` means the user read the book but did not leave a star rating. At first I removed those rows, but later I realized that was wasting useful information. If a user chose to read a book, that is at least weak evidence of interest.

**Hit Rate@K** measures whether the hidden liked book appeared in the top `K` recommendations. The evaluation idea is:

```text
User liked A, B, C, D, E
Hide E
Recommend books using A, B, C, D
Check if E appears in the top K recommendations
```

So `Hit@10 = 30%` means that for about 30% of evaluated users, the hidden liked book appeared somewhere in the top 10 recommendations.

**MRR**, or Mean Reciprocal Rank, measures how early the correct hidden book appears. If the hidden book is ranked first, the score for that user is `1/1 = 1.0`. If it is ranked fifth, the score is `1/5 = 0.2`. If it never appears, it gets `0`. This is why MRR is very important: Hit Rate only asks "did we find it?", but MRR asks "did we rank it near the top?"

**Features** are ALS latent factors. They are not neural network neurons. They are hidden taste dimensions learned for users and books. For example, the model might learn something like "classic literature vs. fantasy", "dark books vs. lighter books", or "YA romance vs. adult literary fiction", but these dimensions are not named manually.

**Lambda** is regularization. It controls how much ALS punishes large user/book factor values. If lambda is too low, the model can overfit. If lambda is too high, the model becomes too cautious and loses useful personalization.

**Iterations** are ALS alternating solve rounds. ALS repeatedly updates user vectors while holding book vectors fixed, then updates book vectors while holding user vectors fixed. More iterations do not always mean a better model.

### Dataset

For the recommendation dataset, I used the UCSD Goodreads user-book interactions dataset. The raw interactions file is large, around 4.1GB, so it cannot be treated like a normal small CSV. The pipeline reads it in chunks and creates smaller prepared artifacts for training.

The raw interactions file contained:

| Dataset stage | Rows / interactions | Users | Books | Notes |
|---|---:|---:|---:|---|
| Raw rows scanned | 228,648,342 | - | - | Complete Goodreads interactions CSV |
| Explicit rating rows | 104,551,549 | - | - | Rows where `rating > 0` |
| Read-unrated rows | 7,579,654 | - | - | Rows where `rating == 0` and `is_read == 1` |
| Explicit-only filtered file | 99,361,816 | 750,325 | 724,641 | Users with at least 5 ratings, books with at least 10 ratings |
| Read-aware filtered file | 106,929,763 | 766,036 | 777,324 | Explicit ratings plus read-unrated rows |

The first filtering step was simple but important:

- keep users with at least `5` observed interactions
- keep books with at least `10` observed interactions
- for the explicit-only dataset, count only ratings
- for the read-aware dataset, count both explicit ratings and read-unrated interactions

This filtering is not just for speed. A user who rated only one book does not give the model enough taste information. A book rated by only one or two people also does not give the model enough collaborative signal. Netflix, as far as I know, filters out users with less than 20 interactions.

For the final validation setup, I created a proper train/validation split before training. This matters because the older evaluation was more optimistic: it hid one liked book temporarily during evaluation, but the model had still already seen that book during training.

The proper split works like this:

```text
Choose 10,000 users with enough 5-star books
Remove one 5-star book per user before training
Train the model without those 10,000 rows
Evaluate whether the model can recommend the hidden books back
```

The validation split created:

| Split artifact | Rows |
|---|---:|
| Original read-aware interactions | 106,929,763 |
| Training rows after removing holdout books | 106,919,763 |
| Validation holdout rows | 10,000 |
| Candidate books for validation | 20,000 |

So when I say `validation 20k`, it means the model is choosing recommendations from a 20,000-book candidate universe, and the hidden books were removed before training.

### Level 1 Model - Popularity baseline

Level 1 has to be mentioned in order for Levels 2 and 3 to make sense. It is the level that I mostly skipped because it is too simple, but it is still useful.

The Level 1 model is basically a popularity model. It recommends the most popular books based on amount of interactions, average rating, or a weighted combination of rating and popularity. It does not understand taste. It does not understand that a user likes classics, fantasy, or romance. It only says, "many people liked this, so maybe you will too."

This is not impressive as AI, but it is still useful as a fallback for new users with no history.

### Level 2 Model - Item collaborative filtering

This one is harder, which is why I started here. The Level 2 model finds taste neighbors. So if User A liked Books A, B, C, and D, and User B liked Books A, B, and C, then Book D can appear in User B's recommendations.

This is still not deep Machine Learning. There is no training loop, no learned latent vectors, and no matrix factorization. But it is still impressive because it uses other people's behavior to recommend books.

Testing similar books to `Pride and Prejudice` came back with books like:

- `Sense and Sensibility`
- `Jane Eyre`
- `Emma`
- `Little Women`
- `To Kill a Mockingbird`
- `Persuasion`
- `The Great Gatsby`

That was the first "wait, this actually works" moment. It was just eyeballing at first, but then I started using Hit Rate@K and MRR to measure it properly.

At first, I defined "liked" as rating `>= 4`. Then I made a stricter model where "liked" meant only rating `= 5`. The stricter version performed better:

| Model | Eval setup | Hit@5 | Hit@10 | Hit@20 | Hit@50 | MRR |
|---|---|---:|---:|---:|---:|---:|
| Level 2 Item-CF, rating >= 4 | old 5k restricted | 16.46% | 22.22% | 31.32% | 46.62% | 0.1236 |
| Level 2 Item-CF, rating = 5 | old 5k restricted | 19.20% | 25.58% | 34.03% | 48.38% | 0.1494 |

So the first lesson was that not all positive signals are equal. A 5-star rating was cleaner than mixing 4-star and 5-star ratings together.

### Level 3 Model - ALS, where Machine Learning begins

For the Machine Learning model, I used ALS, which stands for Alternating Least Squares.

ALS learns two matrices:

- a user matrix, where each user gets a vector of hidden taste features
- a book matrix, where each book gets a vector of hidden content/taste features

For each user vector, the core ALS math looks like this:

```text
A = Y.T @ Y  +  Y_obs.T @ (C - I) @ Y_obs  +  lambda * I
b = Y_obs.T @ (C * p)
x = solve(A, b)
```

In plain English, `Y` is the book-factor matrix, `Y_obs` is the part of that matrix for the books this user interacted with, `C` is confidence, `p` is preference, and `lambda` is regularization. The model solves this equation to get the best user vector `x` given the current book vectors, then it does the same thing, vice versa, for books.

The model predicts how much a user will like a book by comparing the user's vector with the book's vector. In simple terms:

```text
predicted preference = user_vector dot book_vector
```

The "learning" part is ALS repeatedly improving, "optimizing" these vectors. It fixes the book vectors and solves for better user vectors. Then it fixes the user vectors and solves for better book vectors. It keeps alternating until the vectors become useful.

The first ALS model used only 5-star ratings. It was my first actual matrix factorization model, but it lost to the Level 2 model:

| Model | Eval setup | Hit@5 | Hit@10 | Hit@20 | Hit@50 | MRR |
|---|---|---:|---:|---:|---:|---:|
| Level 2 Item-CF, rating = 5 | old 5k restricted | 19.20% | 25.58% | 34.03% | 48.38% | 0.1494 |
| Level 3 ALS first pass, 5-star only | old 5k restricted | 15.72% | 23.04% | 32.68% | 48.29% | 0.1105 |

So that was not supposed to happen, but it also made sense after thinking about it. The first ALS model was too sparse. It only knew about 5-star ratings and ignored everything else.

### Mean-centering - adding rating density

Then I decided to add density for ALS to find patterns. Previously, we used only 5-star ratings as the signal that a user "liked" a book. Now we used all explicit ratings.

The important change was mean-centering:

```text
centered_rating = rating - user's average rating
```

A 3-star rating from someone who always rates books 4-5 stars is a negative signal. A 3-star rating from someone who usually rates books 1-2 stars is a positive signal. That is much smarter than treating every 3-star rating the same way.

This improved ALS a lot:

| Model | Eval setup | Hit@5 | Hit@10 | Hit@20 | Hit@50 | MRR |
|---|---|---:|---:|---:|---:|---:|
| Level 2 Item-CF, rating = 5 | old 5k restricted | 19.20% | 25.58% | 34.03% | 48.38% | 0.1494 |
| Level 3 ALS 5-star only | old 5k restricted | 15.72% | 23.04% | 32.68% | 48.29% | 0.1105 |
| Level 3 ALS mean-centered explicit | old 5k restricted | 21.68% | 28.77% | 37.36% | 51.32% | 0.1577 |

This was the first ALS model that clearly beat Level 2.

### Read-aware ALS - using rating 0 correctly

Then I remembered that I had removed all rating `0` rows. That was a problem.

Again, rating `0` does not mean the user hated the book. It means the user read the book but did not rate it. That information is valuable.

For example, imagine a user read 30 books but rated only one of them with 5 stars. If I remove all rating `0` rows, the dataset makes it look like this user only ever interacted with one book. That is obviously weaker than the real history.

So I added read-unrated rows as weak positive implicit feedback:

```text
rating > 0:
  use mean-centered explicit rating signal

rating == 0 and is_read == 1:
  preference = 1
  confidence = 1
```

This idea comes from the 2008 paper by Hu, Koren, and Volinsky, "Collaborative Filtering for Implicit Feedback Datasets". The key idea is that preference and confidence are different things. If a user read a book but did not rate it, I should not treat that as a 5-star rating. But I also should not throw it away.

So the model treats read-unrated books as mild positive evidence.

The read-aware ALS baseline improved the 20k model:

| Model | Eval setup | Hit@5 | Hit@10 | Hit@20 | Hit@50 | MRR |
|---|---|---:|---:|---:|---:|---:|
| ALS mean-centered explicit | old 20k | 16.11% | 21.36% | 27.58% | 38.80% | 0.1183 |
| ALS read-aware 64f lambda 0.1 20i | old 20k | 17.23% | 22.56% | 29.66% | 40.18% | 0.1239 |

This confirmed that the rating `0` rows were not noise. They were weak, but useful.

### Proper validation split

After that, I realized another important thing: the old evaluation was useful for fast experiments, but it was not strict enough.

The old evaluator hid a liked book during evaluation, but the model had already seen that interaction during training. That makes the results optimistic.

So I created a real validation split before training:

- select 10,000 users
- hold out one 5-star book per selected user
- remove those 10,000 rows from the training file
- train ALS on the remaining data
- evaluate whether the model recommends the hidden books back

This is a much more honest evaluation, and all final model comparisons use `validation 20k`.

### Hyperparameter experiments

Once the read-aware ALS pipeline worked, I started experimenting with hyperparameters:

- features: `32`, `64`, `86`, `128`, `192`, `256`, `384`
- lambda: `0.01`, `0.1`, `0.2`, `0.5`, `1.0`, `10.0`
- iterations: `10`, `15`, `20`, `30`, `40`, `50`
- candidate books: mainly `20k`, with one `50k` experiment

The most important lesson was that bigger is not automatically better. More features helped for a while, but eventually the benefit became small or started hurting MRR.

Iterations were also surprising. I expected 20 iterations to be better, but 10 iterations was enough. After 10 iterations, the model was mostly done learning useful ranking structure. The more precise reason is that ALS solves the exact mathematical optimum for one side of the matrix at each step, instead of slowly approximating it with tiny gradient updates. More iterations did not improve validation quality. But I learned that in the very end, so all of my experiments took twice more time and computational power than they should've.

The strongest validation experiments:

| Model | Hit@5 | Hit@10 | Hit@20 | Hit@50 | MRR |
|---|---:|---:|---:|---:|---:|
| 256f lambda 0.1 10i | 23.61% | 29.94% | 36.76% | 47.61% | 0.1771 |
| 256f lambda 1.0 10i | 23.73% | 29.94% | 36.85% | 47.66% | 0.1779 |
| 256f lambda 10.0 10i | 23.46% | 29.75% | 36.52% | 47.64% | 0.1759 |
| 384f lambda 0.1 20i | 23.73% | 29.77% | 36.72% | 47.39% | 0.1740 |
| 384f lambda 1.0 10i | 23.96% | 30.00% | 36.94% | 47.55% | 0.1767 |
| 384f lambda 10.0 10i | 23.80% | 29.80% | 36.59% | 47.36% | 0.1739 |

The 384-feature model was interesting, but it basically flatlined. It slightly improved Hit@5, Hit@10, and Hit@20, but it lost on MRR compared with the 256-feature model. That means it found the hidden book a tiny bit more often, but ranked it slightly lower on average.

For recommendations, ranking sharpness matters a lot. A model that puts the right book at rank 3 is usually more useful than a model that puts it at rank 18. That is why I still prefer the 256-feature model.

Training time also matters. A 384-feature model is slower and larger. The 384f 20-iteration run took close to an hour, while the 384f 10-iteration runs took around 14-15 minutes. The 256f 10-iteration models were faster and still gave the best MRR. So the practical winner is not just more accurate in the right way, but also cheaper to train and store.

Current best model:

```text
ALS read-aware mean-centered
candidate books: 20,000
features: 256
lambda: 1.0
iterations: 10
validation: true pre-training holdout
```

### Comparing the best model to the first models

This is the part that makes the progress obvious. The first models were not bad, but the final ALS model is much better at ranking the right book near the top.

| Model | Eval setup | Hit@5 | Hit@10 | Hit@20 | Hit@50 | MRR |
|---|---|---:|---:|---:|---:|---:|
| Level 2 Item-CF, rating >= 4 | old 5k restricted | 16.46% | 22.22% | 31.32% | 46.62% | 0.1236 |
| Level 2 Item-CF, rating = 5 | old 5k restricted | 19.20% | 25.58% | 34.03% | 48.38% | 0.1494 |
| ALS 5-star only | old 5k restricted | 15.72% | 23.04% | 32.68% | 48.29% | 0.1105 |
| ALS mean-centered explicit | old 20k | 16.11% | 21.36% | 27.58% | 38.80% | 0.1183 |
| ALS read-aware 64f lambda 0.1 20i | old 20k | 17.23% | 22.56% | 29.66% | 40.18% | 0.1239 |
| Newest ALS 256f lambda 1.0 10i | true validation 20k | 23.73% | 29.94% | 36.85% | 47.66% | 0.1779 |

There is one caveat: the old Level 2 models were tested on a smaller 5k restricted universe, while the newest ALS model is tested on a harder 20k validation universe. So this is not a perfectly apples-to-apples table.

But even with that caveat, the newest model is clearly stronger. Compared with the best early Level 2 model, the newest ALS model improved:

| Metric | Improvement |
|---|---:|
| Hit@5 | +4.53 percentage points |
| Hit@10 | +4.36 percentage points |
| Hit@20 | +2.82 percentage points |
| MRR | +0.0285 |

Hit@50 is slightly lower than the old Level 2 strict model, but that is not worrying because the newest model chooses from 20k books instead of 5k. The more important signs are Hit@5, Hit@10, Hit@20, and MRR, and all of those improved.

### Current conclusion

The best model right now is:

```text
Read-aware mean-centered implicit ALS
256 features
lambda 1.0
10 iterations
20,000 candidate books
```

This model is the best balance between quality, training time, and ranking sharpness. The 384-feature model is close, but it does not beat the 256-feature model where I care most: MRR.

The biggest lessons so far:

- Level 2 is surprisingly strong and easy to understand.
- ALS only became strong after the data representation became better.
- Mean-centering was a major improvement.
- Rating `0` rows were useful when treated as weak implicit positives.
- A proper validation split is necessary, otherwise the metrics are way too optimistic
- More features and more iterations do not automatically make the model better.
- MRR matters because recommendations are only useful if the good books appear early.

## May 16th, 2026

### Level 4 Model - Hybrid ALS + metadata

After ALS, I moved to a hybrid model. ALS is strong because it learns from user behavior, but it does not know anything about the book itself. It does not know the author, genre, page count, language, average rating, or popularity. That is a problem for cold-start users and cold-start books.

A cold-start user is a user with little or no reading history. ALS cannot know their taste yet, because there is no useful user vector. A cold-start book is a book with too few interactions. ALS cannot recommend it well because the book vector is weak or missing. Metadata helps here, because even if a book has no behavior signal, it still has an author, genre, rating, page count, and other descriptive features.

The hybrid model combines:

```text
final_score = alpha * ALS_score + (1 - alpha) * metadata_score
```

Here, `alpha` controls how much we trust ALS compared with metadata. If `alpha = 0.6`, then the final score is 60% ALS and 40% metadata. Metadata weights control what the metadata side cares about. For example, author weight `0.5` means author similarity is 50% of the metadata score, not 50% of the whole final score.

The metadata score used:

- genre similarity
- author similarity
- average rating similarity
- page count similarity
- popularity
- language similarity

My own instinct was to make author weigh more than other metadata, because this is how I noticed I pick books personally. I enjoyed reading a lot of Rick Riordan's books and George Orwell's, but if I were to look at books of the same genre, I can't say the same. 

So I tested many variations. I changed alpha, changed the metadata weights, tried author-heavy versions, genre-heavy versions, language-aware versions, and tried different candidate pools. In total, this became around 200 hybrid variations. The best one was:

```text
Base model: ALS read-aware mean-centered
features: 256
lambda: 1.0
iterations: 10
alpha: 0.6
genre weight: 0.3
author weight: 0.5
rating weight: 0.1
page count weight: 0.05
popularity weight: 0.05
language weight: 0
candidate strategy: rerank ALS top 500
```

This means the best model used the previous ALS model, then reranked the top ALS candidates using a 60/40 blend of collaborative score and metadata score. It did not beat ALS by making the candidate pool bigger. In fact, when I tried reranking ALS top 1000 instead of top 500, the result got worse. The model found the hidden book in the candidate pool more often, but the ranking became noisier.

The final best model from each major level:

| Level | Model | Eval setup | Hit@5 | Hit@10 | Hit@20 | Hit@50 | MRR |
|---|---|---|---:|---:|---:|---:|---:|
|  2 | Item-CF, rating = 5 | old 5k restricted | 19.20% | 25.58% | 34.03% | 48.38% | 0.1494 |
|  3 | ALS read-aware 256f lambda 1.0 10i | true validation 20k | 23.73% | 29.94% | 36.85% | 47.66% | 0.1779 |
|  4 | Hybrid ALS + metadata | true validation 20k | 24.99% | 30.94% | 37.89% | 48.90% | 0.1869 |

The Level 2 model was evaluated on only 5k candidate books, while the Level 3 and Level 4 models were evaluated on a harder 20k validation universe. That makes the Level 4 result more impressive than it looks at first, because it is choosing from about four times more books and still ranks the hidden liked book better.

In the end, I decided to run the latest model on a user who rated 'Percy Jackson and the Lightning Thief' 5 stars and nothing else. Here are the top 10 results:

1. The Sea of Monsters
2. The Battle of the Labyrinth
3.	The Titan's Curse
4.	The Last Olympian
5.	The Lost Hero
6.	The Lost Hero
7.	The Last Olympian
8.	The Son of Neptune
9.	The Mark of Athena
10.	The House of Hades

Incredible stuff. These are exactly the 9 books that are the direct continuations of 'The Lightning Thief'. Except you wouldn't read 'The Lost Hero' twice, it just got 2 editions here.

Also, some notes to my future self:
1. Start with experimenting with iterations first. Would've saved a ton of time here.
2. Use the validation split from the start to avoid too optimistic results.
3. Test lambda on a log scale. Changing it from 0.1 to 0.2 did absolutely nothing, but 0.01, 0.1, 1.0 and 10.0 all had some differences.
4. Adding more candidates is not automatically better. Ranking quality matters more than candidate pool size.


## May 21st, 2026
The app development continues almost every single day, but I'm gonna group the updates every few days or so:

- Added a fuller reading experience with notes, highlights, and saved vocabulary-style lookup annotations.
- Added dictionary lookup for selected English and Russian words.
- Added LibreTranslate-powered translation for selected English words and passages inside the reader.
- Added multiple app themes and theme switching.
- Added the public-domain demo audiobook path for `The Raven` by Edgar Allan Poe.
- Added a cleaner audiobook player with progress save/resume.
- Added text-to-audio and audio-to-text sync so reading and listening can continue from the same book position.
- Added a user rating history view for checking rated books, stars, and rating dates.


## May 24th, 2026
- Added Google OAuth login and registration.
- Fixed the previously known duplicate books bug.
- Improved the audiobook UI and added background playback so listening can continue even after closing the app.
- Improved the Admin page UI.

## References

- Hu, Y., Koren, Y., & Volinsky, C. (2008). *Collaborative Filtering for Implicit Feedback Datasets*. IEEE International Conference on Data Mining.
- UCSD Goodreads Dataset by Mengting Wan and Julian McAuley: <https://github.com/MengtingWan/goodreads>
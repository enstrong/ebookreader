#!/usr/bin/env python3
"""Prepare a Goodreads subset for import into the ebookreader backend."""

import argparse
import gzip
import json
import time
from pathlib import Path

import pandas as pd
import psycopg2
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


def normalize_author(authors: str) -> str:
    if pd.isna(authors) or not authors:
        return ''
    if isinstance(authors, str):
        return authors.split('/')[0].strip()
    return str(authors).strip()


def normalize_cover_url(url: str) -> str:
    if pd.isna(url) or not url or url == '\\N':
        return ''
    return str(url).strip()


def normalize_external_url(url: str) -> str:
    if pd.isna(url) or not url or url == '\\N':
        return ''
    return str(url).strip()


def normalize_genres(genres) -> str:
    if pd.isna(genres) or not genres:
        return ''
    if isinstance(genres, str):
        return genres.strip()
    if isinstance(genres, (list, tuple)):
        return ';'.join(str(item).strip() for item in genres if item)
    return str(genres).strip()


def normalize_language(language_code) -> str:
    if pd.isna(language_code) or not language_code:
        return ''
    return str(language_code).strip().lower()


def parse_int(value):
    try:
        if pd.isna(value):
            return 0
        return int(value)
    except (ValueError, TypeError):
        return 0


def parse_float(value):
    try:
        if pd.isna(value):
            return 0.0
        return float(value)
    except (ValueError, TypeError):
        return 0.0


def load_books_from_json(path: Path, max_records: int | None = None) -> list[dict]:
    def open_file():
        if path.suffix == '.gz':
            return gzip.open(path, 'rt', encoding='utf-8')
        return open(path, 'rt', encoding='utf-8')

    def normalize_record(raw: dict) -> dict:
        authors = raw.get('authors')
        if isinstance(authors, list):
            author_names = []
            for author in authors:
                if isinstance(author, dict):
                    name = author.get('name')
                else:
                    name = str(author)
                if name:
                    author_names.append(name)
            author = ', '.join(author_names)
        elif isinstance(authors, dict):
            author = authors.get('name', '') or ''
        else:
            author = str(authors or '')

        image_url = raw.get('image_url') or raw.get('imageUrl') or raw.get('small_image_url') or raw.get('large_image_url') or ''
        description = raw.get('description') or raw.get('description_text') or ''
        uri = raw.get('uri') or raw.get('url') or ''
        raw_genres = raw.get('genres') or raw.get('genre') or ''
        if isinstance(raw_genres, dict):
            raw_genres = raw_genres.get('genres', '')

        book_id = raw.get('book_id') or raw.get('bookId') or raw.get('id') or ''

        language_code = raw.get('language_code') or raw.get('languageCode') or raw.get('language')
        num_pages = raw.get('num_pages') or raw.get('numPages') or raw.get('pages')

        return {
            'title': raw.get('title', '') or '',
            'authors': author,
            'description': description,
            'image_url': image_url,
            'average_rating': parse_float(raw.get('average_rating') or raw.get('averageRating')),
            'ratings_count': parse_int(raw.get('ratings_count') or raw.get('ratingsCount')),
            'text_reviews_count': parse_int(raw.get('text_reviews_count') or raw.get('textReviewsCount')),
            'uri': uri,
            'book_id': book_id,
            'genres': normalize_genres(raw_genres),
            'language': normalize_language(language_code),
            'page_count': parse_int(num_pages),
        }

    records = []
    with open_file() as f:
        first = f.readline()
        if not first:
            return records
        stripped = first.lstrip()
        if stripped.startswith('['):
            raw_books = json.loads(first + f.read())
            for raw in raw_books:
                if max_records is not None and len(records) >= max_records:
                    break
                records.append(normalize_record(raw))
        else:
            if stripped:
                records.append(normalize_record(json.loads(stripped)))
            for line in f:
                if max_records is not None and len(records) >= max_records:
                    break
                if not line.strip():
                    continue
                records.append(normalize_record(json.loads(line)))
    return records


COMPLETE_DATASET_FILES = {
    'goodreads_book_works.json.gz',
    'goodreads_book_authors.json.gz',
    'goodreads_book_series.json.gz',
    'goodreads_books.json.gz',
    'goodreads_book_genres_initial.json.gz',
    'book_id_map.csv',
    'user_id_map.csv',
    'goodreads_interactions.csv',
    'goodreads_reviews_dedup.json.gz',
    'goodreads_reviews_spoiler.json.gz',
    'goodreads_reviews_spoiler_raw.json.gz',
}
BY_GENRE_PREFIXES = (
    'goodreads_books_',
    'goodreads_interactions_',
    'goodreads_reviews_',
)

BOOKS_BY_GENRE = {
    'children': 'goodreads_books_children.json.gz',
    'comics_graphic': 'goodreads_books_comics_graphic.json.gz',
    'fantasy_paranormal': 'goodreads_books_fantasy_paranormal.json.gz',
    'history_biography': 'goodreads_books_history_biography.json.gz',
    'mystery_thriller_crime': 'goodreads_books_mystery_thriller_crime.json.gz',
    'poetry': 'goodreads_books_poetry.json.gz',
    'romance': 'goodreads_books_romance.json.gz',
    'young_adult': 'goodreads_books_young_adult.json.gz',
}


def get_dataset_url(file_name: str) -> str:
    if file_name in COMPLETE_DATASET_FILES:
        base = 'https://mcauleylab.ucsd.edu/public_datasets/gdrive/goodreads/'
    elif any(file_name.startswith(prefix) for prefix in BY_GENRE_PREFIXES):
        base = 'https://mcauleylab.ucsd.edu/public_datasets/gdrive/goodreads/byGenre/'
    else:
        raise ValueError(
            f'Unknown dataset file name {file_name!r}. Use a name from the authors\' dataset listing.'
        )
    return base + file_name


def download_dataset_file(file_name: str, output_path: Path, max_retries: int = 5) -> None:
    url = get_dataset_url(file_name)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    session = requests.Session()
    retry = Retry(
        total=max_retries,
        backoff_factor=1,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=frozenset(['GET']),
        raise_on_status=False,
    )
    session.mount('https://', HTTPAdapter(max_retries=retry))

    attempt = 0
    while attempt < max_retries:
        attempt += 1
        try:
            if output_path.exists():
                output_path.unlink()
            print(f'Downloading {file_name} from {url} to {output_path} (attempt {attempt}/{max_retries})')
            with session.get(url, stream=True, timeout=(10, 120), headers={'User-Agent': 'ebookreader-import/1.0'}) as r:
                r.raise_for_status()
                with open(output_path, 'wb') as f:
                    for chunk in r.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
            print(f'Dataset {file_name} has been downloaded!')
            return
        except requests.RequestException as exc:
            if output_path.exists():
                output_path.unlink()
            if attempt >= max_retries:
                raise
            print(f'Download failed: {exc}. Retrying in 5 seconds...')
            time.sleep(5)


def connect_db(args: argparse.Namespace):
    return psycopg2.connect(
        host=args.db_host,
        port=args.db_port,
        dbname=args.db_name,
        user=args.db_user,
        password=args.db_password,
    )


def get_or_create_genre_id(cursor, genre_name: str):
    cursor.execute(
        'SELECT id FROM genres WHERE name = %s',
        (genre_name,)
    )
    row = cursor.fetchone()
    if row:
        return row[0]
    cursor.execute(
        'INSERT INTO genres (name) VALUES (%s) ON CONFLICT (name) DO NOTHING RETURNING id',
        (genre_name,)
    )
    row = cursor.fetchone()
    if row:
        return row[0]
    cursor.execute('SELECT id FROM genres WHERE name = %s', (genre_name,))
    return cursor.fetchone()[0]


def upsert_book(cursor, row):
    if getattr(row, 'goodreads_id', None):
        cursor.execute(
            'SELECT id FROM books WHERE goodreads_id = %s',
            (row.goodreads_id,)
        )
        row_data = cursor.fetchone()
        if row_data:
            return row_data[0]

    cursor.execute(
        'SELECT id FROM books WHERE title = %s',
        (row.title,)
    )
    row_data = cursor.fetchone()
    if row_data:
        return row_data[0]

    cursor.execute(
        '''INSERT INTO books
           (title, author, description, cover_url, goodreads_id, average_rating, ratings_count, review_count, external_url, language, page_count)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
           RETURNING id''',
        (
            row.title,
            row.author,
            row.description,
            row.cover_url,
            row.goodreads_id,
            row.average_rating,
            row.ratings_count,
            row.review_count,
            row.external_url,
            row.language,
            row.page_count,
        )
    )
    created = cursor.fetchone()
    return created[0]


def import_to_db(output, args: argparse.Namespace):
    with connect_db(args) as conn:
        with conn.cursor() as cursor:
            imported = 0
            for row in output.itertuples(index=False):
                book_id = upsert_book(cursor, row)
                genres = [g.strip() for g in (row.genres or '').split(';') if g.strip()]
                for genre_name in genres:
                    genre_id = get_or_create_genre_id(cursor, genre_name)
                    cursor.execute(
                        '''INSERT INTO book_genres (book_id, genre_id)
                           SELECT %s, %s
                           WHERE NOT EXISTS (
                               SELECT 1 FROM book_genres WHERE book_id = %s AND genre_id = %s
                           )''',
                        (book_id, genre_id, book_id, genre_id)
                    )
                imported += 1
            conn.commit()
    print(f'Imported {imported:,} books into the database')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Create a Goodreads subset CSV prepared for backend import.'
    )
    parser.add_argument('--download-file', type=str, help='Dataset file name to download from the authors\' source (for example goodreads_books.json.gz)')
    parser.add_argument('--genre', type=str, choices=list(BOOKS_BY_GENRE.keys()), help='Download and process a smaller by-genre books subset')
    parser.add_argument('--download-dir', type=Path, default=Path('.'), help='Directory to save downloaded dataset files')
    parser.add_argument('--download-only', action='store_true', help='Download the specified dataset file and exit before processing')
    parser.add_argument('--books-json', type=Path, help='Path to Goodreads metadata JSON file (json or json.gz)')
    parser.add_argument('--books-csv', type=Path, default=Path('books.csv'), help='Path to the Goodreads books CSV fallback')
    parser.add_argument('--output-csv', type=Path, default=Path('goodreads_subset_for_import.csv'), help='Path to write the filtered import CSV')
    parser.add_argument('--min-ratings', type=int, default=50, help='Minimum ratings_count to include a book')
    parser.add_argument('--max-books', type=int, default=10000, help='Maximum number of books to include in the subset')
    parser.add_argument('--max-input-books', type=int, default=None, help='Maximum number of records to read from the JSON/CSV source before filtering')
    parser.add_argument('--include-no-cover', action='store_true', help='Keep books without a cover URL and record empty coverUrl values')
    parser.add_argument('--db-import', action='store_true', help='Also import the filtered subset into Postgres')
    parser.add_argument('--db-host', type=str, default='localhost', help='Postgres host')
    parser.add_argument('--db-port', type=int, default=5432, help='Postgres port')
    parser.add_argument('--db-name', type=str, default='ebookreader', help='Postgres database name')
    parser.add_argument('--db-user', type=str, default='postgres', help='Postgres user')
    parser.add_argument('--db-password', type=str, default='12345', help='Postgres password')
    parser.add_argument('--verbose', action='store_true', help='Print processing details')
    return parser.parse_args()


def main():
    args = parse_args()

    if args.genre and args.download_file:
        raise ValueError('Specify either --genre or --download-file, not both.')

    if args.genre:
        args.download_file = BOOKS_BY_GENRE[args.genre]

    if args.download_file:
        downloaded_path = args.download_dir / args.download_file
        download_dataset_file(args.download_file, downloaded_path)
        if args.download_only:
            return
        if args.books_json is None and downloaded_path.suffix in ('.json', '.gz'):
            args.books_json = downloaded_path

    if args.books_json:
        if not args.books_json.exists():
            raise FileNotFoundError(f'Books JSON not found: {args.books_json}')
        print(f'Loading books from {args.books_json}')
        records = load_books_from_json(args.books_json, max_records=args.max_input_books)
        books = pd.DataFrame(records)
        print(f'Loaded {len(books):,} books from JSON')
    else:
        if not args.books_csv.exists():
            raise FileNotFoundError(f'Books CSV not found: {args.books_csv}')
        print(f'Loading books from {args.books_csv}')
        if args.max_input_books:
            books = pd.read_csv(args.books_csv, nrows=args.max_input_books)
        else:
            books = pd.read_csv(args.books_csv)
        print(f'Loaded {len(books):,} books from CSV')

    if 'ratings_count' not in books.columns:
        raise ValueError('The input books data must include a ratings_count field.')

    if 'image_url' not in books.columns:
        print('Warning: input books data does not include image_url. coverUrl will be empty.')

    if 'genres' not in books.columns:
        print('Warning: input books data does not include genres. genres will be empty.')

    if 'authors' in books.columns:
        books['author'] = books['authors'].apply(normalize_author)
    else:
        books['author'] = ''

    if 'image_url' in books.columns:
        books['cover_url'] = books['image_url'].apply(normalize_cover_url)
    else:
        books['cover_url'] = ''

    if 'book_id' in books.columns:
        books['goodreads_id'] = books['book_id'].astype(str)
    else:
        books['goodreads_id'] = ''

    if 'text_reviews_count' in books.columns:
        books['review_count'] = books['text_reviews_count'].fillna(0).astype(int)
    else:
        books['review_count'] = 0

    if 'uri' in books.columns:
        books['external_url'] = books['uri'].apply(normalize_external_url)
    else:
        books['external_url'] = ''

    if 'genres' in books.columns:
        books['genres'] = books['genres'].apply(normalize_genres)
    else:
        books['genres'] = ''

    if 'language' in books.columns:
        books['language'] = books['language'].apply(normalize_language)
    else:
        books['language'] = ''

    if 'page_count' not in books.columns:
        books['page_count'] = 0

    books = books.sort_values(by='ratings_count', ascending=False)
    books = books[books['ratings_count'] >= args.min_ratings]
    if not args.include_no_cover:
        books = books[books['cover_url'].astype(bool)]

    books = books.head(args.max_books)

    output = books[
        ['title', 'author', 'description', 'cover_url', 'goodreads_id',
         'average_rating', 'ratings_count', 'review_count', 'external_url',
         'genres', 'language', 'page_count']
    ].copy()
    output['description'] = output['description'].fillna('').astype(str).str.slice(0, 2000)
    output.to_csv(args.output_csv, index=False)
    print(f'Wrote {len(output):,} rows to {args.output_csv}')

    if args.db_import:
        import_to_db(output, args)


if __name__ == '__main__':
    main()

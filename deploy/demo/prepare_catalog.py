#!/usr/bin/env python3
"""Build the demo's catalog from the same 20k candidate universe as the real model."""
import csv
import gzip
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
metadata = ROOT / 'data/recommendations/hybrid/book_metadata_workcanon_20k_i5.csv'
authors_file = ROOT / 'data/goodreads/goodreads_book_authors.json.gz'
authors = {}
if authors_file.exists():
    with gzip.open(authors_file, 'rt') as source:
        for line in source:
            row = json.loads(line)
            authors[row['author_id']] = row['name']
with (ROOT / 'goodreads_catalog_seed_20k.csv').open() as source:
    legacy = {row['goodreads_id']: row for row in csv.DictReader(source)}
books = []
with metadata.open() as source:
    for row in csv.DictReader(source):
        book_id = row['goodreads_book_id']
        old = legacy.get(book_id, {})
        author_ids = row['author'].split(',')
        names = list(dict.fromkeys(authors.get(a.strip(), '') for a in author_ids))
        names = [name for name in names if name]
        books.append({
            'goodreadsId': book_id,
            'title': row['title'][:1000],
            'author': ', '.join(names)[:1000] or old.get('author', 'Unknown author')[:1000],
            'description': old.get('description', '')[:2000],
            'coverUrl': old.get('cover_url', '')[:1000],
            'externalUrl': old.get('external_url', f'https://www.goodreads.com/book/show/{book_id}')[:1000],
            'averageRating': float(row['average_rating'] or 0),
            'ratingsCount': int(float(row['ratings_count'] or 0)),
            'pageCount': int(float(row['page_count'] or 0)),
            'language': row['language'][:64] or 'en',
            'genres': [g.strip() for g in row['genres'].split(';') if g.strip()],
        })
output = ROOT / 'build/demo/catalog.json'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(books, ensure_ascii=False))
print(f'Prepared {len(books)} model candidates in {output}')

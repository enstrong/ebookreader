#!/usr/bin/env python3
"""Exercise the public deployment with disposable visitor sessions (no account credentials)."""
import io
import json
import sys
import urllib.error
import urllib.request
import uuid
import zipfile

BASE = sys.argv[1].rstrip('/')

def request(path, token=None, method='GET', payload=None, headers=None, expected=200):
    headers = dict(headers or {})
    if token: headers['Authorization'] = 'Bearer ' + token
    if isinstance(payload, dict):
        payload = json.dumps(payload).encode()
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(BASE+path, data=payload, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            status, data, content_type = response.status, response.read(), response.headers.get('Content-Type','')
    except urllib.error.HTTPError as error:
        status, data, content_type = error.code, error.read(), error.headers.get('Content-Type','')
    assert status in (expected if isinstance(expected,tuple) else (expected,)), f'{method} {path}: expected {expected}, received {status}: {data[:180]!r}'
    return json.loads(data) if data and 'json' in content_type else data

def upload(token, name, content):
    boundary = uuid.uuid4().hex
    payload = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode()
               + content + f'\r\n--{boundary}--\r\n'.encode())
    return request('/api/demo/uploads',token,'POST',payload,{'Content-Type':f'multipart/form-data; boundary={boundary}'})

sessions=[]
try:
    for _ in range(2): sessions.append(request('/api/demo/session',method='POST')['token'])
    a,b=sessions
    assert request('/api/demo/session',a)['token']
    request('/api/user/profile',expected=403)
    request('/api/user/profile','invalid-token',expected=401)
    request('/api/auth/register',method='POST',expected=(403,404))
    raven=request('/api/books/demo-audiobook',a)
    book_id=raven['id']
    assert request(f'/api/books/{book_id}/chapters',a)
    assert request(f'/api/user/books/{book_id}/annotations',a)
    request(f'/api/user/books/{book_id}/progress',a,'PUT',{'segmentOrder':1,'segmentProgress':0.42,'lastMode':'TEXT','audioPositionMs':12345})
    progress=request(f'/api/user/books/{book_id}/progress',a)
    assert abs(progress['segmentProgress']-0.42)<0.001
    assert request(f'/api/user/books/{book_id}/progress',b)['segmentProgress'] != 0.42
    request(f'/api/user/books/{book_id}/rating',a,'PUT',{'rating':2})
    note=request(f'/api/user/books/{book_id}/annotations',a,'POST',{'chapterOrder':1,'startOffset':0,'endOffset':4,'highlightedText':'Once','note':'Smoke test note','color':'#14FFEC'})
    other=request(f'/api/user/books/{book_id}/annotations',b)
    assert all(row['id']!=note['id'] for row in other)
    formats={'private.txt': b'A private uploaded book. A second sentence.',
             'private.fb2': b'<FictionBook><body><section><title>Chapter one</title><p>A private FB2 book.</p></section></body></FictionBook>'}
    epub=io.BytesIO()
    with zipfile.ZipFile(epub,'w') as z:
        z.writestr('META-INF/container.xml','<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>')
        z.writestr('content.opf','<package><metadata><title>Private EPUB</title></metadata><manifest><item id="one" href="one.xhtml"/></manifest><spine><itemref idref="one"/></spine></package>')
        z.writestr('one.xhtml','<html><body><p>A private EPUB chapter.</p></body></html>')
    formats['private.epub']=epub.getvalue()
    uploaded=[]
    for name,data in formats.items():
        book=upload(a,name,data); uploaded.append(book['id'])
        request(f'/api/books/{book["id"]}',a)
        request(f'/api/books/{book["id"]}',b,expected=404)
        request(f'/api/books/{book["id"]}',expected=404)
    recommendations=request('/api/recommendations/me?limit=10',a)
    assert len(recommendations['recommendations']) >= 5
    assert all(row.get('model') == 'hybrid_als_metadata' for row in recommendations['recommendations'])
    translated=request('/api/lookup/selection',a,'POST',{'text':'Good morning, my friend.','sourceLanguage':'en','targetLanguage':'ru'})
    assert translated.get('translation',{}).get('text') and translated['translation'].get('source')=='libretranslate', f'Translation missing: {translated}'
    tracks=request(f'/api/books/{book_id}/audio-tracks',a)
    data=request(f'/api/books/{book_id}/audio-tracks/{tracks[0]["id"]}/stream',headers={'Range':'bytes=0-1023'},expected=206)
    assert len(data)==1024
    request('/api/demo/session',a,'DELETE',expected=204); sessions.remove(a)
    request('/api/user/profile',a,expected=401)
    for book_id in uploaded: request(f'/api/books/{book_id}',b,expected=404)
    print('PASS: automatic accounts, seeded books/notes/ratings, database progress, private TXT/FB2/EPUB uploads, real model recommendations, translation, audio ranges, isolation, session revocation.')
finally:
    for token in sessions:
        try: request('/api/demo/session',token,'DELETE',expected=204)
        except Exception as error: print(f'Cleanup will also run automatically: {error}',file=sys.stderr)

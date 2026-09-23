#!/usr/bin/env python3
"""Validate README image content, including badges that return errors with HTTP200."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import html
from html.parser import HTMLParser
import io
import json
import mimetypes
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlsplit
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET
import zlib

from PIL import Image, ImageSequence

MAX_BYTES = 10 * 1024 * 1024
ERROR_LABEL = re.compile(
    r'\b(?:badge not found|not found|inaccessible|invalid|service unavailable|'
    r'rate limited|no longer available)\b|(?:^|:\s*)(?:error|404)(?:\b|$)', re.I)


class ImageContentError(ValueError):
    def __init__(self, message, visible_label=''):
        super().__init__(message)
        self.visible_label = visible_label


class Images(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.images = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == 'img':
            values['src'] = values.get('src') or ''
        if tag == 'img' or (tag == 'source' and 'srcset' in values):
            self.images.append(values)


def _closing_bracket(text: str, start: int) -> int:
    depth = 1
    index = start
    while index < len(text):
        if text[index] == '\\':
            index += 2
            continue
        if text[index] == '[':
            depth += 1
        elif text[index] == ']':
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return -1


def _destination(text: str) -> str:
    text = text.lstrip()
    if text.startswith('<'):
        return text[1:text.index('>')] if '>' in text else ''
    result = []
    depth = 0
    index = 0
    while index < len(text):
        character = text[index]
        if character == '\\' and index + 1 < len(text):
            index += 1
            result.append(text[index])
        elif character.isspace() or (character == ')' and depth == 0):
            break
        else:
            if character == '(':
                depth += 1
            elif character == ')':
                depth -= 1
            result.append(character)
        index += 1
    return ''.join(result)


def extract_images(markdown: str) -> list[str]:
    # Code examples and comments are not rendered images.
    visible = re.sub(r'(?ms)^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?^ {0,3}\1[^\n]*$', '', markdown)
    visible = re.sub(r'(`+)(?:(?!\1).)*?\1', '', visible, flags=re.S)
    visible = re.sub(r'<!--.*?-->', '', visible, flags=re.S)
    references = {re.sub(r'\s+', ' ', name).strip().casefold(): _destination(value)
                  for name, value in re.findall(r'^ {0,3}\[([^\]]+)\]:\s*(.+)$', visible, re.M)}
    urls = []
    for match in re.finditer(r'(?<!\\)!\[', visible):
        end = _closing_bracket(visible, match.end())
        if end < 0:
            continue
        label = visible[match.end():end]
        tail = visible[end + 1:]
        if tail.startswith('('):
            urls.append(_destination(tail[1:]))
        else:
            if tail.startswith('[') and ']' in tail:
                label = tail[1:tail.index(']')] or label
            key = re.sub(r'\s+', ' ', label).strip().casefold()
            if key in references:
                urls.append(references[key])
    parser = Images()
    parser.feed(visible)
    for image in parser.images:
        if 'src' in image:
            urls.append(image['src'])
        if 'srcset' in image:
            urls.extend(candidate.strip().split()[0]
                        for candidate in (image['srcset'] or '').split(',') if candidate.strip())
    decoded = [html.unescape(url) for url in urls]
    return list(dict.fromkeys('https:' + url if url.startswith('//') else url for url in decoded))


def github_proxies(rendered_html: str) -> dict[str, str]:
    parser = Images()
    parser.feed(rendered_html)
    return {image['data-canonical-src']: image['src'] for image in parser.images
            if image.get('data-canonical-src') and
            urlsplit(image.get('src', '')).scheme == 'https' and
            urlsplit(image.get('src', '')).hostname == 'camo.githubusercontent.com'}


def _read_response(reply, url: str, attempt: int) -> dict:
    body = reply.read(MAX_BYTES + 1)
    if len(body) > MAX_BYTES:
        raise ValueError('Image response exceeds the size limit')
    encoding = reply.headers.get('Content-Encoding', '').lower().strip()
    try:
        if encoding == 'gzip':
            with gzip.GzipFile(fileobj=io.BytesIO(body)) as stream:
                body = stream.read(MAX_BYTES + 1)
        elif encoding == 'deflate':
            decoder = zlib.decompressobj()
            body = decoder.decompress(body, MAX_BYTES + 1)
            if not decoder.eof:
                raise ValueError('Incomplete deflate response')
        elif encoding not in ('', 'identity'):
            raise ValueError(f'Unsupported content encoding: {encoding}')
    except (OSError, EOFError, zlib.error) as error:
        raise ValueError(f'Invalid compressed image response: {error}') from error
    if len(body) > MAX_BYTES:
        raise ValueError('Decoded image exceeds the size limit')
    return dict(status=reply.status, body=body,
                content_type=reply.headers.get('Content-Type', ''),
                final_url=reply.geturl() or url, attempts=attempt)


def fetch_image(url: str, *, opener=urlopen, sleep=time.sleep) -> dict:
    """Use at most three GET attempts for transport, 429 or 5xx failures."""
    result = {}
    for attempt in range(1, 4):
        request = Request(url, headers={'User-Agent': 'restart-app-image-check/1.0',
                                       'Accept-Encoding': 'gzip, deflate'})
        try:
            try:
                reply = opener(request, timeout=15)
            except HTTPError as error:
                reply = error
            with reply:
                result = _read_response(reply, url, attempt)
            if result['status'] != 429 and result['status'] < 500:
                return result
        except (URLError, TimeoutError, ConnectionError, OSError) as error:
            result = dict(status=None, content_type='', body=b'', final_url=url,
                          attempts=attempt, transport_error=str(error))
        except (ValueError, zlib.error) as error:
            return dict(status=None, content_type='', body=b'', final_url=url,
                        attempts=attempt, content_error=str(error))
        if attempt < 3:
            sleep(attempt)
    return result


def _content(body: bytes, content_type: str) -> dict:
    kind = content_type.split(';', 1)[0].strip().lower()
    if kind == 'image/svg+xml' or body.lstrip().startswith((b'<svg', b'<?xml')):
        root = ET.fromstring(body)
        if root.tag.rsplit('}', 1)[-1] != 'svg':
            raise ValueError('Image XML does not contain an SVG root')
        labels = []
        for node in root.iter():
            if node.tag.rsplit('}', 1)[-1] in ('title', 'text'):
                labels.append(' '.join(''.join(node.itertext()).split()))
            if node.get('aria-label'):
                labels.append(' '.join(node.attrib['aria-label'].split()))
        labels = list(dict.fromkeys(label for label in labels if label))
        label = ' | '.join(labels)
        if any(ERROR_LABEL.search(value) for value in labels):
            raise ImageContentError(f'SVG error badge: {label}', label)
        if kind != 'image/svg+xml':
            raise ValueError(f'SVG has the wrong content type: {content_type}')
        return dict(format='SVG', visible_label=label)
    signatures = [(b'\x89PNG\r\n\x1a\n', 'PNG'), (b'\xff\xd8\xff', 'JPEG'),
                  (b'GIF87a', 'GIF'), (b'GIF89a', 'GIF')]
    expected = next((name for prefix, name in signatures if body.startswith(prefix)), None)
    if body.startswith(b'RIFF') and body[8:12] == b'WEBP':
        expected = 'WEBP'
    if expected is None or not kind.startswith('image/'):
        raise ValueError(f'Unsupported image signature/content type: {content_type}')
    with Image.open(io.BytesIO(body)) as image:
        if image.format != expected:
            raise ValueError('Image decoder disagrees with the file signature')
        dimensions = list(image.size)
        image.verify()
    with Image.open(io.BytesIO(body)) as image:
        for frame in ImageSequence.Iterator(image):
            frame.load()
    return dict(format=expected, dimensions=dimensions, visible_label='')


def check_image(url: str, root: Path, *, fetcher=fetch_image,
                proxies: dict[str, str] | None = None) -> dict:
    result = dict(url=url, ok=False, evidence_source='direct', visible_label='')
    try:
        parsed = urlsplit(url)
        if parsed.scheme in ('http', 'https'):
            reply = fetcher(url)
        elif not parsed.scheme and not parsed.netloc and parsed.path:
            path = (root / unquote(parsed.path)).resolve()
            if not path.is_relative_to(root.resolve()):
                raise ValueError('Local image points outside the repository')
            reply = dict(body=path.read_bytes(), status=200, attempts=1,
                         content_type=mimetypes.guess_type(path)[0] or '', final_url=url)
            result['evidence_source'] = 'local'
        else:
            raise ValueError('Missing image URL or unsupported URL scheme')
        result.update({key: value for key, value in reply.items() if key != 'body'})
        # An explicit image-content error must never be hidden by old cache.
        if reply.get('content_error'):
            raise ValueError(reply['content_error'])
        if reply['status'] != 200:
            if (reply['content_type'].split(';', 1)[0] == 'image/svg+xml' or
                    reply['body'].lstrip().startswith(b'<svg')):
                _content(reply['body'], reply['content_type'])
            blocked = reply['status'] is None or reply['status'] in (403, 429) or reply['status'] >= 500
            proxy = (proxies or {}).get(url)
            if not blocked or not proxy:
                raise ValueError(f'Direct image unavailable: HTTP {reply["status"]}; {reply.get("transport_error", "")}')
            result['direct_status'] = reply['status']
            result['direct_attempts'] = reply['attempts']
            result['direct_content_type'] = reply['content_type']
            result['direct_error'] = reply.get('transport_error', f'HTTP {reply["status"]}')
            result.pop('transport_error', None)
            result['evidence_source'] = 'github_canonical_proxy'
            result['proxy_url'] = proxy
            reply = fetcher(proxy)
            result.update({key: value for key, value in reply.items() if key != 'body'})
            if reply['status'] != 200 or reply.get('content_error'):
                raise ValueError('Matching GitHub image proxy is also unavailable')
        result['bytes'] = len(reply['body'])
        result['sha256'] = hashlib.sha256(reply['body']).hexdigest()
        result.update(_content(reply['body'], reply['content_type']))
        result['ok'] = True
    except (ValueError, OSError, ET.ParseError, SyntaxError, EOFError,
            Image.DecompressionBombError) as error:
        result['error'] = str(error)
        if isinstance(error, ImageContentError):
            result['visible_label'] = error.visible_label
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--readme', type=Path, default=Path('README.md'))
    parser.add_argument('--output', type=Path, default=Path('readme-images.json'))
    parser.add_argument('--github-page', help='Rendered GitHub README URL for labeled proxy evidence')
    args = parser.parse_args()
    proxies = {}
    if args.github_page:
        location = urlsplit(args.github_page)
        if location.scheme != 'https' or location.hostname != 'github.com':
            parser.error('--github-page must be an HTTPS github.com URL')
        page = fetch_image(args.github_page)
        if page['status'] == 200:
            proxies = github_proxies(page['body'].decode('utf-8', errors='replace'))
    urls = extract_images(args.readme.read_text(encoding='utf-8'))
    results = []
    for url in urls:
        result = check_image(url, args.readme.resolve().parent, proxies=proxies)
        results.append(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)
    report = dict(readme=str(args.readme), image_count=len(results),
                  ok=bool(results) and all(item['ok'] for item in results), images=results)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    if not report['ok']:
        raise SystemExit('README image-content validation failed; see the JSON report.')


if __name__ == '__main__':
    main()

"""Content checks for README images, including HTTP200 error badges."""
import gzip
import io
from pathlib import Path
import tempfile
import unittest
from urllib.error import HTTPError, URLError

from PIL import Image

from check_readme_images import check_image, extract_images, fetch_image, github_proxies


def response(body, content_type='image/svg+xml', status=200):
    return dict(status=status, content_type=content_type, body=body,
                final_url='https://images.example/badge', attempts=1)


class ReadmeImagesTest(unittest.TestCase):
    def test_extracts_actual_markdown_html_and_reference_images(self):
        text = '''[![badge](https://img.example/a_(b).svg "title")](https://site.example)
<img src="https://img.example/icon.png?a=1&amp;b=2" alt="icon">
![name][logo]
![shortcut]
[logo]: <https://img.example/logo.svg> "logo"
[shortcut]: https://img.example/shortcut.png
`![inline](https://ignored.example/inline.png)`
```md
![code](https://ignored.example/code.png)
```
<!-- <img src="https://ignored.example/comment.png"> -->
'''
        self.assertEqual(set(extract_images(text)), {
            'https://img.example/a_(b).svg',
            'https://img.example/icon.png?a=1&b=2',
            'https://img.example/logo.svg', 'https://img.example/shortcut.png',
        })

    def test_rejects_http200_error_labels_in_any_svg_text_surface(self):
        for text in ['<title>404: badge not found</title>',
                     '<text>inaccessible</text>', '<text>invalid</text>',
                     '<g aria-label="pub: error"/>']:
            with self.subTest(text=text):
                fetch = lambda url: response(f'<svg xmlns="http://www.w3.org/2000/svg">{text}</svg>'.encode())
                result = check_image('https://img.example/badge.svg', Path('.'), fetcher=fetch,
                                     proxies={'https://img.example/badge.svg': 'https://camo.githubusercontent.com/cached'})
                self.assertFalse(result['ok'])
                self.assertEqual(result['evidence_source'], 'direct')
                self.assertIn('error badge', result['error'])
                self.assertTrue(result['visible_label'])

    def test_extracts_responsive_images_and_keeps_missing_sources_as_failures(self):
        self.assertEqual(extract_images('<img src="//img.example/a.png" '
                                        'srcset="https://img.example/b.png 2x">'
                                        '<source srcset="https://img.example/c.png 1x">'
                                        '<img src>'),
                         ['https://img.example/a.png', 'https://img.example/b.png',
                          'https://img.example/c.png', ''])
        self.assertFalse(check_image('', Path('.'))['ok'])

    def test_accepts_dynamic_valid_badges_including_pending_zero_points(self):
        for title in ['pub: v1.10.0', 'likes: 900', 'points: 0/0', 'points: 160/160']:
            result = check_image('https://img.example/badge', Path('.'),
                                 fetcher=lambda url: response(f'<svg><title>{title}</title></svg>'.encode()))
            self.assertTrue(result['ok'], result)
            self.assertEqual(result['visible_label'], title)

    def test_rejects_html_malformed_svg_and_truncated_raster(self):
        image = io.BytesIO()
        Image.new('RGB', (3, 2)).save(image, format='PNG')
        for data, content_type in [(b'<html>blocked</html>', 'text/html'),
                                   (b'<svg><title>', 'image/svg+xml'),
                                   (image.getvalue()[:40], 'image/png')]:
            with self.subTest(content_type=content_type):
                result = check_image('https://img.example/icon', Path('.'),
                                     fetcher=lambda url: response(data, content_type))
                self.assertFalse(result['ok'])
        valid = check_image('https://img.example/icon', Path('.'),
                            fetcher=lambda url: response(image.getvalue(), 'image/png'))
        self.assertTrue(valid['ok'], valid)
        self.assertEqual(valid['dimensions'], [3, 2])

    def test_proxy_evidence_only_after_blocked_direct_transport(self):
        url = 'https://img.example/badge'
        proxy = 'https://camo.githubusercontent.com/proxy'
        calls = []
        def fetch(value):
            calls.append(value)
            return (response(b'Forbidden', 'text/plain', 403) if value == url else
                    response(b'<svg><title>points: 0/0</title></svg>'))
        result = check_image(url, Path('.'), fetcher=fetch, proxies={url: proxy})
        self.assertTrue(result['ok'], result)
        self.assertEqual(result['evidence_source'], 'github_canonical_proxy')
        self.assertEqual(result['direct_status'], 403)
        self.assertEqual(calls, [url, proxy])
        # A missing endpoint is a real failure, not a reason to use old cache.
        result = check_image(url, Path('.'), proxies={url: proxy},
                             fetcher=lambda value: response(b'Not Found', 'text/plain', 404))
        self.assertFalse(result['ok'])
        self.assertEqual(result['evidence_source'], 'direct')

    def test_proxy_mapping_requires_matching_canonical_url_and_github_host(self):
        html = '<img src="https://camo.githubusercontent.com/a" data-canonical-src="https://img.example/a">'
        html += '<img src="https://unrelated.example/a" data-canonical-src="https://img.example/b">'
        self.assertEqual(github_proxies(html), {'https://img.example/a': 'https://camo.githubusercontent.com/a'})

    def test_fetch_retries_transient_failures_and_decodes_gzip(self):
        class Reply(io.BytesIO):
            status = 200
            headers = {'Content-Type': 'image/svg+xml', 'Content-Encoding': 'gzip'}
            def geturl(self):
                return 'https://img.example/badge'
        body = b'<svg><title>points: 0/0</title></svg>'
        calls = []
        def opener(request, timeout):
            calls.append(request)
            if len(calls) == 1:
                raise URLError('temporary outage')
            if len(calls) == 2:
                raise HTTPError(request.full_url, 429, 'limited', {}, io.BytesIO(b'limited'))
            return Reply(gzip.compress(body))
        result = fetch_image('https://img.example/badge', opener=opener, sleep=lambda _: None)
        self.assertEqual(result['body'], body)
        self.assertEqual(result['attempts'], 3)
        calls.clear()
        def unavailable(request, timeout):
            calls.append(request)
            raise HTTPError(request.full_url, 503, 'down', {}, io.BytesIO(b'down'))
        self.assertEqual(fetch_image('https://img.example/badge', opener=unavailable,
                                    sleep=lambda _: None)['status'], 503)
        self.assertEqual(len(calls), 3)

    def test_local_image_cannot_escape_repository(self):
        with tempfile.TemporaryDirectory() as directory:
            result = check_image('../private.png', Path(directory))
            self.assertFalse(result['ok'])
            self.assertIn('outside', result['error'])

    def test_invalid_compression_is_content_failure_without_proxy_fallback(self):
        class Reply(io.BytesIO):
            status = 200
            headers = {'Content-Type': 'image/svg+xml', 'Content-Encoding': 'gzip'}
            def geturl(self):
                return 'https://img.example/badge'
        result = fetch_image('https://img.example/badge',
                             opener=lambda request, timeout: Reply(b'not gzip'),
                             sleep=lambda _: None)
        self.assertIn('content_error', result)
        checked = check_image('https://img.example/badge', Path('.'),
                              fetcher=lambda url: result,
                              proxies={'https://img.example/badge': 'https://camo.githubusercontent.com/old'})
        self.assertFalse(checked['ok'])
        self.assertEqual(checked['evidence_source'], 'direct')


if __name__ == '__main__':
    unittest.main()

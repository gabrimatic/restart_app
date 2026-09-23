"""Exercise the real HTTP fixture server used by built browser applications."""

from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import urlopen

from serve_web_probe import Handler


class WebProbeServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='restart_web_server_')
        directory = Path(cls.temporary.name)
        (directory / 'index.html').write_text('<title>Built application</title>')
        (directory / 'main.dart.wasm').write_bytes(b'\0asm\x01\0\0\0')
        cls.server = ThreadingHTTPServer(
            ('127.0.0.1', 0), partial(Handler, directory=str(directory)))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f'http://127.0.0.1:{cls.server.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.temporary.cleanup()

    def test_non_root_route_falls_back_to_application(self):
        with urlopen(self.base + '/probe/deep/route?case=default') as response:
            self.assertEqual(response.read(), b'<title>Built application</title>')
            self.assertEqual(response.headers['Cache-Control'], 'no-store')

    def test_wasm_has_correct_type_and_opaque_origin_cors(self):
        with urlopen(self.base + '/main.dart.wasm') as response:
            self.assertEqual(response.headers['Content-Type'], 'application/wasm')
            self.assertEqual(response.headers['Access-Control-Allow-Origin'], '*')
            self.assertEqual(response.read(), b'\0asm\x01\0\0\0')

    def test_fixture_routes_do_not_resolve_to_flutter_index(self):
        for name, title in [('before', 'Before restart probe'),
                            ('parent', 'Opaque-origin restart probe')]:
            with self.subTest(name=name):
                with urlopen(self.base + f'/__restart_probe__/{name}.html?target=/probe') as response:
                    self.assertIn(f'<title>{title}</title>', response.read().decode())

    def test_missing_resource_is_not_silently_replaced_by_html(self):
        with self.assertRaises(HTTPError) as caught:
            urlopen(self.base + '/missing.wasm')
        self.assertEqual(caught.exception.code, 404)
        caught.exception.close()


if __name__ == '__main__':
    unittest.main()

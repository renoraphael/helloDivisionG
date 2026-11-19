#!/usr/bin/env python3
"""Create a private connected copy; never modifies the supplied original HTML."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
if args.source.resolve() == args.output.resolve():
    parser.error('Choose a different output file; keep the original unchanged.')
root = Path(__file__).parent
source = args.source.read_text()
js = (root / 'cloud-sync.js').read_text()
css = (root / 'cloud-sync.css').read_text()
if 'hdg-cloud-adapter' in source:
    parser.error('Use the original unmodified v475 HTML as input.')
changes = {
    "const KEY = 'tm_division_g_dashboard_v56';": "const KEY = 'tm_division_g_dashboard_cloud_v1';",
    "const DURABLE_DB_NAME = 'hello_division_g_durable_v1';": "const DURABLE_DB_NAME = 'hello_division_g_cloud_v1';",
    'const DURABLE_INIT_PROMISE=initializeDurableStorage();': 'const DURABLE_INIT_PROMISE=HDGCloud.boot();'
}
for before, after in changes.items():
    if source.count(before) != 1:
        parser.error('Unexpected app version; required integration point not found exactly once: ' + before)
    source = source.replace(before, after, 1)
assert '</script' not in js.lower()
source = source.replace('<head>', '<head>\n<style id="hdg-cloud-styles">' + css + '</style>\n<script id="hdg-cloud-adapter">' + js + '</script>', 1)
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(source)
print('Created private sync copy. Original unchanged. Legacy embedded data remains: do not publish this file.')

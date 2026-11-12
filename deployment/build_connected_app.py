#!/usr/bin/env python3
"""Build a private connected app from an offline HTML release. Never publish its output."""
import argparse
from pathlib import Path

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('source',type=Path)
parser.add_argument('output',type=Path)
parser.add_argument('--version',required=True)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
if args.source.resolve()==args.output.resolve():parser.error('Keep the supplied original unchanged; choose a separate output.')
if args.output.resolve().is_relative_to((root/'docs').resolve()):parser.error('Connected HTML contains private records and cannot be built into the public Pages folder.')
source=args.source.read_text()
if 'hdg-cloud-adapter' in source:parser.error('Use the unmodified offline HTML, not an already connected build.')
changes={
 "const KEY = 'tm_division_g_dashboard_v56';":"const KEY = 'tm_division_g_dashboard_cloud_v1';",
 "const DURABLE_DB_NAME = 'hello_division_g_durable_v1';":"const DURABLE_DB_NAME = 'hello_division_g_cloud_v1';",
 'const DURABLE_INIT_PROMISE=initializeDurableStorage();':'const DURABLE_INIT_PROMISE=HDGCloud.boot();'
}
for old,new in changes.items():
 if source.count(old)!=1:parser.error('Missing or ambiguous integration point: '+old)
 source=source.replace(old,new,1)
js=(root/'docs/cloud-sync.js').read_text();css=(root/'docs/cloud-sync.css').read_text()
if '</script' in js.lower():parser.error('Adapter contains an unsafe closing script delimiter.')
if '<head>' not in source[:1000]:parser.error('Expected a document head near the start of the HTML.')
import json
injection='<style id="hdg-cloud-styles">'+css+'</style>\n<script id="hdg-cloud-adapter">'+js+'</script>\n<script id="hdg-release">window.__HDG_APP_RELEASE__='+json.dumps(args.version)+';</script>'
source=source.replace('<head>','<head>\n'+injection,1)
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(source)
print('Private connected build created; offline source unchanged. Never commit the generated HTML.')

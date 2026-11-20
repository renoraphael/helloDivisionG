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
# Hosted clients load the shared database. Do not silently replay offline roster,
# nickname, or attendance seeds against an approved officer's shared records.
if args.version in ('v632', 'v632-community', 'v633', 'v633-community', 'v634', 'v634-community', 'v637', 'v637-community'):
 for migration in ('migrateNov09OfficialRosterV445','migrateNov16OfficialRosterV603'):
  line=f'  candidate={migration}(candidate);\n'
  if source.count(line)!=1:parser.error('Missing or ambiguous embedded roster migration: '+migration)
  source=source.replace(line,'',1)
 # Projects & Meetings contains director-only notes. Hosted authorization
 # currently operates on an officer-readable snapshot, not individual fields.
 hosted_route="    if(id==='projects' && u.role!=='division-director') return false; /* v614: private to the Division Director */"
 if source.count(hosted_route)!=1:parser.error('Missing or ambiguous director workspace route.')
 source=source.replace(hosted_route,"    if(id==='projects') return false; /* Hosted workspace requires server-side authorization. */",1)
 workspace_link=next((line for line in source.splitlines(keepends=True) if 'href="#projects" data-tab="projects"' in line),None)
 if not workspace_link or source.count(workspace_link)!=1:parser.error('Missing or ambiguous director workspace navigation.')
 source=source.replace(workspace_link,'',1)
 blocks=('v526-nickname-seed','v527-nickname-update','v614-projects-workspace','v615-tli2-surabaya','v617-past-exco')
 for block in blocks:
  tag=f'<script id="{block}">'
  if source.count(tag)!=1:parser.error('Missing or ambiguous hosted exclusion: '+block)
  start=source.index(tag)
  end=source.index('</script>',start)+len('</script>')
  source=source[:start]+source[end:]
js=(root/'docs/cloud-sync.js').read_text();css=(root/'docs/cloud-sync.css').read_text()
# The adapter's Member loader names the closing tag inside a JS string; '<\/script>' is the same string but cannot end the inline script early.
js=js.replace('</script','<\\/script')
if '</script' in js.lower():parser.error('Adapter contains an unsafe closing script delimiter.')
if '<head>' not in source[:1000]:parser.error('Expected a document head near the start of the HTML.')
import json
injection='<style id="hdg-cloud-styles">'+css+'</style>\n<script id="hdg-cloud-adapter">'+js+'</script>\n<script id="hdg-release">window.__HDG_APP_RELEASE__='+json.dumps(args.version)+';</script>'
source=source.replace('<head>','<head>\n'+injection,1)
if args.version in ('v632-community', 'v633-community', 'v634-community', 'v637-community'):
 ballot=(root/'deployment/hosted-ballot.js').read_text()
 before, close, after=source.rpartition('</body>')
 if '</script' in ballot.lower() or not close:
  parser.error('Could not add the hosted ballot integration.')
 source=before+'<script id="hdg-hosted-ballot">'+ballot+'</script>\n'+close+after

args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(source)
print('Private connected build created; offline source unchanged. Never commit the generated HTML.')

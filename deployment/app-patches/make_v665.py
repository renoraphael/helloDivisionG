"""Build HelloDivisionG_v665.html from v664. The offline app is unchanged apart from its version: v665 is the release
in which the hosted Leader app saves member list imports to the member database (deployment/member-import.js, schema 018)."""
import sys, hashlib
src, out, want = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src, encoding='utf-8').read()
assert hashlib.sha256(s.encode()).hexdigest() == want, 'unexpected v664 file'
assert s.count('<title>Hello Division G! v664</title>') == 1
s = s.replace('<title>Hello Division G! v664</title>', '<title>Hello Division G! v665</title>')
open(out, 'w', encoding='utf-8').write(s)
print('v665 written', hashlib.sha256(s.encode()).hexdigest())

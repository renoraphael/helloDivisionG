"""Build HelloDivisionG_v666.html from v665. The offline app is unchanged apart from its version: v666 is the release
in which the hosted Leader app imports member and officer lists of other divisions into the member database (schema 019)."""
import sys, hashlib
src, out, want = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src, encoding='utf-8').read()
assert hashlib.sha256(s.encode()).hexdigest() == want, 'unexpected v665 file'
assert s.count('<title>Hello Division G! v665</title>') == 1
s = s.replace('<title>Hello Division G! v665</title>', '<title>Hello Division G! v666</title>')
open(out, 'w', encoding='utf-8').write(s)
print('v666 written', hashlib.sha256(s.encode()).hexdigest())

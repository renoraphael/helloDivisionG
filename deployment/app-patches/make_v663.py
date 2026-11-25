import sys, hashlib, pathlib
src, out = sys.argv[1], sys.argv[2]
here = pathlib.Path(__file__).parent / 'v663'
s = open(src, encoding='utf-8').read()
assert hashlib.sha256(s.encode()).hexdigest() == sys.argv[3], 'unexpected v662'
D = 'dialog.v663-dlg' + ':is(#v663Editor,#v663ClubDlg)' * 3
css = (here / 'editors.css').read_text().replace('$D', D)
js = (here / 'editors.js').read_text()
assert '</script' not in js.lower()
block = f'<style id="v663-event-editors-style">\n{css}</style>\n<script id="v663-event-editors">\n{js}</script>\n'
i = s.rfind('</body>'); assert i > 0
s = s[:i] + block + s[i:]
assert s.count('<title>Hello Division G! v662</title>') == 1
s = s.replace('<title>Hello Division G! v662</title>', '<title>Hello Division G! v663</title>')
open(out, 'w', encoding='utf-8').write(s)
print('v663 written', hashlib.sha256(s.encode()).hexdigest())

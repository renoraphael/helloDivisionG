"""Build HelloDivisionG_v664.html from v663: replace the v663 editor block with the v664 one (editors in the row)."""
import sys, hashlib, pathlib
src, out, want = sys.argv[1], sys.argv[2], sys.argv[3]
here = pathlib.Path(__file__).parent / 'v664'
s = open(src, encoding='utf-8').read()
assert hashlib.sha256(s.encode()).hexdigest() == want, 'unexpected v663 file'
D = '.v663-dlg' + ':is(#v663Editor,#v663ClubDlg)' * 3
css = (here / 'editors.css').read_text().replace('$D', D)
js = (here / 'editors.js').read_text()
assert '</script' not in js.lower()
a = s.index('<style id="v663-event-editors-style">')
b = s.index('</script>', s.index('<script id="v663-event-editors">')) + len('</script>\n')
s = s[:a] + f'<style id="v663-event-editors-style">\n{css}</style>\n<script id="v663-event-editors">\n{js}</script>\n' + s[b:]
assert s.count('<title>Hello Division G! v663</title>') == 1
s = s.replace('<title>Hello Division G! v663</title>', '<title>Hello Division G! v664</title>')
open(out, 'w', encoding='utf-8').write(s)
print('v664 written', hashlib.sha256(s.encode()).hexdigest())

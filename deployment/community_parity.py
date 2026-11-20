"""Community-tab behaviour shared by the Member and Leader builds.

community_parity_patches.txt holds the behaviour changes made for the Member app (Agenda parser and Poster start empty,
explicit Open in Agenda, Resume last poster, Agenda attendance default and selector, venue default order, themed Agenda
stage). They only rewrite UI behaviour; nothing here swaps in Member-only data. The text is the same code that
build_member_v632.py applies, kept here so the Leader build can apply it too. `apply(source)` returns the transformed HTML."""
import re
from pathlib import Path


def apply(source):
    ns = {'re': re, 'source': source}

    def segment(start, end, replacement):
        s = ns['source']
        before = s.index(start)
        after = s.index(end, before + len(start))
        ns['source'] = s[:before] + replacement + s[after:]

    def replace(before, after):
        s = ns['source']
        assert s.count(before) == 1, before[:80]
        ns['source'] = s.replace(before, after, 1)

    def remove_script(name):
        s = ns['source']
        start = s.index('<script id="' + name + '">')
        end = s.index('</script>', start) + len('</script>')
        ns['source'] = s[:start] + s[end:]

    ns.update(segment=segment, replace=replace, remove_script=remove_script)
    code = (Path(__file__).with_name('community_parity_patches.txt')).read_text()
    exec(compile(code, 'community_parity_patches.txt', 'exec'), ns)
    return ns['source']

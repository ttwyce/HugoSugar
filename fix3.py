p = 'lib/core/ai/tools/builtin_tools.dart'
lines = open(p, encoding='utf-8').read().split('\n')

idx = None
for i, l in enumerate(lines):
    if l.startswith('// \u2500\u2500 \u8bb0\u5fc6'):
        idx = i
        break
assert idx is not None, 'marker not found'
print('marker at', idx + 1)

j = idx - 1
while j >= 0 and lines[j].strip() == '':
    j -= 1
assert lines[j].strip() == '}', 'expected } above marker, got %r' % lines[j]
print('removing stray } at line', j + 1)
del lines[j]

txt = '\n'.join(lines)
old2 = "      detail: '\u5220\u9664\u4e00\u6761\u8bb0\u5fc6',\n    );\n  }\nclass _CachedPage {"
new2 = "      detail: '\u5220\u9664\u4e00\u6761\u8bb0\u5fc6',\n    );\n  }\n}\n\nclass _CachedPage {"
assert old2 in txt, 'tail not found'
txt = txt.replace(old2, new2, 1)

open(p, 'w', encoding='utf-8').write(txt)
print('ok')
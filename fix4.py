p = 'lib/core/ai/tools/builtin_tools.dart'
lines = open(p, encoding='utf-8').read().split('\n')

# 找到 class _CachedPage 前一行，插入 "  }" 和 "}" 补齐结构
target = None
for i, l in enumerate(lines):
    if l.startswith('class _CachedPage'):
        target = i
        break
assert target is not None
print('class _CachedPage at line', target + 1)

# 前面应当是 "    );" 之后直接是 "}"
prev = target - 1
print('prev line:', repr(lines[prev]))
assert lines[prev] == '}', 'unexpected: %r' % lines[prev]

# 把那个错位的 "}" 换成 方法闭合 + 类闭合 + 空行
lines[prev:prev + 1] = ['  }', '}', '']
open(p, 'w', encoding='utf-8').write('\n'.join(lines))
print('patched')
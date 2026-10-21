p = 'lib/features/ai/chat_page.dart'
s = open(p, encoding='utf-8').read()

old = """     required this.onResend,
     required this.onEdit,"""
new = """     required this.onResend,
     required this.onRegenerate,
     required this.onEdit,"""
assert old in s, 'ctor'
s = s.replace(old, new, 1)

old2 = """   final VoidCallback onResend;
   final VoidCallback onEdit;"""
new2 = """   final VoidCallback onResend;

   /// 保留旧回答，再生成一次
   final VoidCallback onRegenerate;

   final VoidCallback onEdit;"""
assert old2 in s, 'fields'
s = s.replace(old2, new2, 1)

old3 = "                                onResend: () => _resend(entries[i]),"
new3 = ("                                onResend: () => _resend(entries[i]),\n"
        "                                onRegenerate: () => _regenerate(entries[i]),")
assert old3 in s, 'call'
s = s.replace(old3, new3, 1)

open(p, 'w', encoding='utf-8').write(s)
print('ok')
p = 'lib/features/settings/settings_page.dart'
s = open(p, encoding='utf-8').read()

# import
anchor = "import '../../core/ai/ai_controller.dart';"
assert anchor in s, 'anchor import'
if "import 'memory_page.dart';" not in s:
    s = s.replace(anchor, anchor + "\nimport 'memory_page.dart';", 1)

# 入口：放在 System Prompt 之后、token 上限之前
old = """          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('单轮 token 上限'),"""
new = """          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.psychology_outlined),
            title: const Text('记忆库'),
            subtitle: Text(
              _memorySubtitle(),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _openMemory,
          ),
          const IndentedDivider(),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('单轮 token 上限'),"""
assert old in s, 'insert point'
s = s.replace(old, new, 1)

open(p, 'w', encoding='utf-8').write(s)
print('ok')
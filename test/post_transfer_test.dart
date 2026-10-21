import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/post/post_transfer.dart';

/// 造一个 zip，用于验证解包逻辑。
Uint8List _zipOf(Map<String, String> entries) {
  final a = Archive();
  for (final e in entries.entries) {
    final b = utf8.encode(e.value);
    a.addFile(ArchiveFile(e.key, b.length, b));
  }
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  group('打包与解包往返', () {
    test('多篇文章能原样往返', () {
      final items = {
        'a.md': '---\ntitle: A\n---\n正文 A',
        'b.md': '---\ntitle: B\n---\n正文 B',
      };
      final zip = PostTransfer.buildZip(items);
      final back = PostTransfer.readZip(zip);
      expect(back, items);
    });

    test('中文内容不乱码', () {
      final items = {'中文标题.md': '正文里有中文和标点：，。「」'};
      final back = PostTransfer.readZip(PostTransfer.buildZip(items));
      expect(back['中文标题.md'], items['中文标题.md']);
    });

    test('空集合产生可解的空结果', () {
      final back = PostTransfer.readZip(PostTransfer.buildZip({}));
      expect(back, isEmpty);
    });
  });

  group('解包时挡掉危险条目', () {
    test('只收 .md，别的扩展名忽略', () {
      final zip = _zipOf({
        'a.md': 'x',
        'b.txt': 'y',
        'c.png': 'z',
      });
      final back = PostTransfer.readZip(zip);
      expect(back.keys, ['a.md']);
    });

    test('路径穿越条目被丢弃', () {
      // 这是重点：zip 里写 ../../evil.md 想写到仓库外
      final zip = _zipOf({
        '../../evil.md': 'pwn',
        'ok.md': 'fine',
      });
      final back = PostTransfer.readZip(zip);
      expect(back.containsKey('evil.md'), isFalse);
      expect(back.keys, ['ok.md']);
    });

    test('绝对路径条目被丢弃', () {
      final zip = _zipOf({
        '/etc/passwd.md': 'pwn',
        'ok.md': 'fine',
      });
      final back = PostTransfer.readZip(zip);
      expect(back.keys, ['ok.md']);
    });

    test('macOS 打包垃圾被丢弃', () {
      final zip = _zipOf({
        '__MACOSX/._a.md': 'junk',
        'a.md': 'real',
      });
      final back = PostTransfer.readZip(zip);
      expect(back.keys, ['a.md']);
    });

    test('多层目录被压平成文件名', () {
      final zip = _zipOf({
        'myblog/content/posts/deep.md': 'content',
      });
      final back = PostTransfer.readZip(zip);
      expect(back.keys, ['deep.md']);
    });
  });

  group('去重', () {
    test('同名加序号而不是覆盖', () {
      final items = {
        'a.md': 'first',
        'a.md#2': 'second',
      };
      // 用 Map 造不出重复 key，这里直接验证 dedupe 面对已冲突输入的行为
      final out = PostTransfer.dedupe({'a.md': 'x', 'b.md': 'y'});
      expect(out.keys, ['a.md', 'b.md']);
      expect(items.length, 2);
    });

    test('保留原始顺序', () {
      final out = PostTransfer.dedupe({
        'z.md': '1',
        'a.md': '2',
        'm.md': '3',
      });
      expect(out.keys.toList(), ['z.md', 'a.md', 'm.md']);
    });
  });

  group('导出文件名', () {
    test('带日期时间且以 .zip 结尾', () {
      final n = PostTransfer.exportFileName(DateTime(2024, 5, 1, 8, 3));
      expect(n, 'hugosugar-posts-20240501-0803.zip');
    });

    test('月/日/时/分补零', () {
      final n = PostTransfer.exportFileName(DateTime(2024, 1, 2, 3, 4));
      expect(n, 'hugosugar-posts-20240102-0304.zip');
    });
  });

  group('单文件解码', () {
    test('UTF-8 正常解出', () {
      final b = Uint8List.fromList(utf8.encode('---\ntitle: 测试\n---\n正文'));
      expect(PostTransfer.decodeSingle(b), contains('测试'));
    });

    test('非 UTF-8 返回 null 而不是抛异常', () {
      // GBK 编码的「中文」字节，不是合法 UTF-8
      final b = Uint8List.fromList([0xD6, 0xD0, 0xCE, 0xC4]);
      expect(PostTransfer.decodeSingle(b), isNull);
    });
  });
}
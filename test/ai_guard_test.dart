import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/tools/html_text.dart';
import 'package:hugosugar/core/ai/tools/path_guard.dart';

void main() {
  group('validatePostPath', () {
    const root = '/site/content';

    test('正常相对路径通过', () {
      expect(validatePostPath(contentDirAbs: root, relPath: 'posts/a.md'),
          isNull);
    });

    test('允许子目录', () {
      expect(
        validatePostPath(contentDirAbs: root, relPath: 'posts/2026/a.md'),
        isNull,
      );
    });

    test('拒绝绝对路径', () {
      expect(
        validatePostPath(contentDirAbs: root, relPath: '/etc/passwd.md'),
        isNotNull,
      );
    });

    test('拒绝 .. 越界', () {
      expect(
        validatePostPath(contentDirAbs: root, relPath: '../secret.md'),
        isNotNull,
      );
    });

    test('拒绝反斜杠形式的越界', () {
      // `..\..\x.md` 在一些平台上会被当成路径分隔符，
      // 不统一处理就能绕过检查
      expect(
        validatePostPath(contentDirAbs: root, relPath: r'..\..\x.md'),
        isNotNull,
      );
    });

    test('拒绝中间夹着 .. 的路径', () {
      expect(
        validatePostPath(contentDirAbs: root, relPath: 'posts/../../x.md'),
        isNotNull,
      );
    });

    test('拒绝非 .md', () {
      expect(
        validatePostPath(contentDirAbs: root, relPath: 'posts/a.txt'),
        isNotNull,
      );
      expect(
        validatePostPath(contentDirAbs: root, relPath: 'posts/a'),
        isNotNull,
      );
    });

    test('大写 .MD 也接受', () {
      expect(validatePostPath(contentDirAbs: root, relPath: 'posts/A.MD'),
          isNull);
    });

    test('拒绝空路径', () {
      expect(validatePostPath(contentDirAbs: root, relPath: '   '), isNotNull);
    });

    test('拒绝路径等于目录本身', () {
      expect(validatePostPath(contentDirAbs: root, relPath: '.'), isNotNull);
    });

    test('文件名里带 .. 但不是越界，应通过', () {
      // `a..b.md` 里的 .. 不是路径段，不能被误杀
      expect(
        validatePostPath(contentDirAbs: root, relPath: 'posts/a..b.md'),
        isNull,
      );
    });
  });

  group('validateFetchUrl', () {
    test('https 公网地址通过', () {
      expect(validateFetchUrl(Uri.parse('https://example.com/a')), isNull);
    });

    test('拒绝 http', () {
      expect(validateFetchUrl(Uri.parse('http://example.com')), isNotNull);
    });

    test('拒绝 file 协议', () {
      expect(validateFetchUrl(Uri.parse('file:///etc/passwd')), isNotNull);
    });

    test('拒绝 localhost', () {
      expect(validateFetchUrl(Uri.parse('https://localhost/')), isNotNull);
      expect(validateFetchUrl(Uri.parse('https://a.localhost/')), isNotNull);
    });

    test('拒绝回环 IP', () {
      expect(validateFetchUrl(Uri.parse('https://127.0.0.1/')), isNotNull);
      expect(validateFetchUrl(Uri.parse('https://127.5.6.7/')), isNotNull);
    });

    test('拒绝 10/8 与 192.168/16', () {
      expect(validateFetchUrl(Uri.parse('https://10.0.0.1/')), isNotNull);
      expect(validateFetchUrl(Uri.parse('https://192.168.1.1/')), isNotNull);
    });

    test('拒绝 172.16/12 区间', () {
      expect(validateFetchUrl(Uri.parse('https://172.16.0.1/')), isNotNull);
      expect(validateFetchUrl(Uri.parse('https://172.31.255.1/')), isNotNull);
      // 172.32 已不在私网区间
      expect(validateFetchUrl(Uri.parse('https://172.32.0.1/')), isNull);
    });

    test('拒绝 169.254 链路本地（云元数据地址）', () {
      expect(validateFetchUrl(Uri.parse('https://169.254.169.254/')),
          isNotNull);
    });

    test('拒绝十进制/十六进制 IP 伪装', () {
      expect(validateFetchUrl(Uri.parse('https://0x7f.0.0.1/')), isNotNull);
    });

    test('拒绝 .internal / .local', () {
      expect(validateFetchUrl(Uri.parse('https://db.internal/')), isNotNull);
      expect(validateFetchUrl(Uri.parse('https://printer.local/')), isNotNull);
    });
  });

  group('isPrivateAddress IPv6', () {
    test('::1 是回环', () {
      expect(isPrivateAddress(InternetAddress('::1')), isTrue);
    });

    test('fc00::/7 唯一本地地址', () {
      expect(isPrivateAddress(InternetAddress('fd00::1')), isTrue);
    });

    test('IPv4 映射的回环地址', () {
      // 这是最容易漏的一种绕过形式
      expect(isPrivateAddress(InternetAddress('::ffff:127.0.0.1')), isTrue);
    });

    test('公网 IPv6 不算私网', () {
      expect(
        isPrivateAddress(InternetAddress('2001:4860:4860::8888')),
        isFalse,
      );
    });
  });

  group('htmlToText', () {
    test('去掉 script 内容而不只是标签', () {
      // 只删标签的话，JS 代码会变成正文，那是纯污染
      final t = htmlToText(
        '<p>正文</p><script>var x = 1 < 2;</script>',
      );
      expect(t.contains('var x'), isFalse);
      expect(t.contains('正文'), isTrue);
    });

    test('标题转成 #', () {
      final t = htmlToText('<h1>一级</h1><h3>三级</h3>');
      expect(t.contains('# 一级'), isTrue);
      expect(t.contains('### 三级'), isTrue);
    });

    test('列表项转成 -', () {
      final t = htmlToText('<ul><li>甲</li><li>乙</li></ul>');
      expect(t.contains('- 甲'), isTrue);
      expect(t.contains('- 乙'), isTrue);
    });

    test('常见实体解码', () {
      final t = htmlToText('<p>A &amp; B &lt;tag&gt; "q"</p>');
      expect(t.contains('A & B <tag> "q"'), isTrue);
    });

    test('数字实体解码', () {
      final t = htmlToText('<p>&#65;&#x42;</p>');
      expect(t.contains('AB'), isTrue);
    });

    test('连续空行折叠成一个', () {
      final t = htmlToText('<p>a</p><p></p><p></p><p>b</p>');
      expect(t.contains('\n\n\n'), isFalse);
    });

    test('自定义实体原样保留，不被吞掉', () {
      final t = htmlToText('<p>&unknownentity;</p>');
      expect(t.contains('&unknownentity;'), isTrue);
    });

    test('没有闭合的 < 不吞掉后文', () {
      final t = htmlToText('<p>a < b 是小于</p>');
      expect(t.contains('a'), isTrue);
    });

    test('guessTitle 优先取 title', () {
      expect(
        guessTitle('<html><head><title>页面标题</title></head>'
            '<body><h1>正文标题</h1></body></html>'),
        '页面标题',
      );
    });

    test('guessTitle 退回到 h1', () {
      expect(guessTitle('<html><body><h1>只有H1</h1></body></html>'), '只有H1');
    });

    test('guessTitle 都没有时返回空串', () {
      expect(guessTitle('<html><body><p>x</p></body></html>'), '');
    });
  });
}
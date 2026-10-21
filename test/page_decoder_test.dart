import 'dart:convert';
import 'dart:io';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugosugar/core/ai/tools/html_text.dart';
import 'package:hugosugar/core/ai/tools/page_decoder.dart';

/// 网页字符集检测与解码。
///
/// 用户的原始反馈：抓 `https://godoor.net/.../gb/hdc01.htm` 得到
/// 「ʥ���γ�--�����̽���」这种乱码。
///
/// 根因不是「解码失败」，而是 `utf8.decode(allowMalformed: true)`
/// 把 GBK 字节**静默**替换成 `�`，然后照常喂给模型 ——
/// 所以这些测试的断言重点是「中文必须完整可读」，
/// 而不是「不抛异常」。
void main() {
  group('从 HTTP 头检测', () {
    test('content-type 带 charset', () {
      final cs = PageDecoder.detectCharset(
        utf8.encode('<html>hi</html>'),
        contentType: 'text/html; charset=utf-8',
      );
      expect(cs, 'utf-8');
    });

    test('charset 大小写与空格无关', () {
      final cs = PageDecoder.detectCharset(
        const [0x3C],
        contentType: 'text/html;  CHARSET = GB2312 ',
      );
      expect(cs, 'gb2312');
    });

    test('content-type 没有 charset 时不能误判', () {
      // 真实场景：godoor.net 只返回 "text/html"
      final bytes = _gbk('<html><body>中文</body></html>');
      final cs = PageDecoder.detectCharset(
        bytes,
        contentType: 'text/html',
      );
      // 头部没声明，只能靠启发式 → 不是合法 UTF-8 → gbk
      expect(cs, 'gbk');
    });
  });

  group('从 HTML meta 检测', () {
    test('meta http-equiv 形式（2000 年代中文站最常见的写法）', () {
      final html = '<html><head>'
          '<meta http-equiv="Content-Type" '
          'content="text/html; charset=gb2312">'
          '</head><body>中文</body></html>';
      final cs = PageDecoder.detectCharset(_gbk(html), contentType: 'text/html');
      expect(cs, 'gb2312');
    });

    test('HTML5 短形式 meta charset', () {
      final html = '<!doctype html><html><head><meta charset="gbk">'
          '</head><body>中文</body></html>';
      final cs = PageDecoder.detectCharset(_gbk(html));
      expect(cs, 'gbk');
    });

    test('xml 声明里的 encoding', () {
      const html = '<?xml version="1.0" encoding="gbk"?><a>中文</a>';
      final cs = PageDecoder.detectCharset(_gbk(html));
      expect(cs, 'gbk');
    });

    test('HTTP 头优先于 meta', () {
      // 服务器说 utf-8，页面里却写着 gb2312 —— 以服务器为准
      final html = '<meta charset="gb2312"><body>hello</body>';
      final cs = PageDecoder.detectCharset(
        utf8.encode(html),
        contentType: 'text/html; charset=utf-8',
      );
      expect(cs, 'utf-8');
    });
  });

  group('启发式', () {
    test('合法 UTF-8 → utf-8', () {
      final cs = PageDecoder.detectCharset(utf8.encode('<p>中文内容</p>'));
      expect(cs, 'utf-8');
    });

    test('非法 UTF-8 字节序列 → gbk', () {
      final cs = PageDecoder.detectCharset(_gbk('<p>中文内容</p>'));
      expect(cs, 'gbk');
    });

    test('纯 ASCII → utf-8（两者等价）', () {
      final cs = PageDecoder.detectCharset(ascii.encode('<p>hello</p>'));
      expect(cs, 'utf-8');
    });

    test('UTF-8 BOM 优先识别', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('<p>中文</p>')];
      expect(PageDecoder.detectCharset(bytes), 'utf-8');
    });
  });

  group('解码结果正确', () {
    test('GBK 页面解出完整中文，不出现替换字符', () {
      const src = '<html><head>'
          '<meta http-equiv="Content-Type" content="text/html; charset=gb2312">'
          '</head><body><p>圣经课程：第一课 唯一的安慰</p></body></html>';

      final out = PageDecoder.decode(
        _gbk(src),
        contentType: 'text/html', // 故意不给 charset，模拟真实站点
      );

      expect(out, contains('圣经课程'));
      expect(out, contains('第一课'));
      expect(out, contains('唯一的安慰'));
      // 关键断言：不能有任何 U+FFFD
      expect(out.contains('\uFFFD'), isFalse, reason: '不应残留替换字符');
    });

    test('UTF-8 页面照旧正常', () {
      const src = '<html><body><p>中文标题</p></body></html>';
      final out = PageDecoder.decode(
        utf8.encode(src),
        contentType: 'text/html; charset=utf-8',
      );
      expect(out, contains('中文标题'));
    });

    test('标成 gb2312 但实际含 GBK 扩展字也能解', () {
      // 用 GB18030/GBK 才有的字验证「GB 系统一按 GBK 解」的策略
      const src = '<meta charset="gb2312"><body>镕 堃 喆</body>';
      final out = PageDecoder.decode(_gbk(src));
      expect(out, contains('镕'));
      expect(out, contains('堃'));
    });

    test('未知字符集不抛异常', () {
      final out = PageDecoder.decode(
        ascii.encode('hello'),
        contentType: 'text/plain; charset=x-unknown-thing',
      );
      expect(out, 'hello');
    });

    test('空字节返回空串', () {
      expect(PageDecoder.decode(const []), '');
    });

    test('BOM 不进入正文', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('正文')];
      final out = PageDecoder.decode(bytes);
      expect(out.startsWith('正文'), isTrue);
    });
  });

  group('端到端：GBK 页面 → 标题 + 正文', () {
    test('标题和正文都不乱码', () {
      const src = '<html><head>'
          '<title>圣经课程--基督教教义: 第一课 唯一的安慰</title>'
          '<meta http-equiv="Content-Type" content="text/html; charset=gb2312">'
          '</head><body>'
          '<h2>第一课 唯一的安慰</h2>'
          '<p>问一：你生与死的唯一安慰是什么？</p>'
          '</body></html>';

      final body = PageDecoder.decode(_gbk(src), contentType: 'text/html');
      final title = guessTitle(body);
      final text = htmlToText(body);

      expect(title, contains('圣经课程'));
      expect(title, contains('唯一的安慰'));
      expect(text, contains('你生与死的唯一安慰是什么'));
      expect(title.contains('\uFFFD'), isFalse);
    });
  });

  group('真实站点取样（存在则跑，缺失则跳过）', () {
    final sample = File('/tmp/gf_raw.bin');
    if (!sample.existsSync()) {
      // CI / 干净环境下没有这份样本，跳过而不是失败
      return;
    }

    test('godoor.net 实际返回的 GBK 字节能正确解码', () {
      final bytes = sample.readAsBytesSync();
      // 真实响应头就是 "text/html"，没有 charset
      final body = PageDecoder.decode(bytes, contentType: 'text/html');

      expect(body, contains('圣经课程'));
      expect(body, contains('基督教教义'));
      expect(body, contains('唯一的安慰'));
      expect(body.contains('\uFFFD'), isFalse);
    });
  });
}

/// 用 GBK 编码构造测试字节。
///
/// 直接调 `fast_gbk` 的 encoder —— 与实现用的是同一个编码表，
/// 避免「测试自己造一套编码、和实现不一致」这种假通过。
List<int> _gbk(String s) => gbk.encode(s);
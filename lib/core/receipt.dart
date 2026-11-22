import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models.dart';
import 'format.dart';

class ReceiptOptions {
  const ReceiptOptions({
    this.paperMm = 58,
    this.showCashier = true,
    this.businessName = 'titik',
    this.branchName = '',
    this.footer = 'Terima kasih',
  });
  final int paperMm;
  final bool showCashier;
  final String businessName;
  final String branchName;
  final String footer;

  /// Lebar karakter: 32 untuk 58 mm, 48 untuk 80 mm.
  int get cols => paperMm >= 80 ? 48 : 32;
}

String _ascii(String s) => s.replaceAll('−', '-').replaceAll('×', 'x').replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

/// Membungkus teks panjang ke beberapa baris selebar [w] kolom.
List<String> _wrap(String text, int w) {
  final out = <String>[];
  var cur = '';
  for (var word in _ascii(text).split(' ')) {
    while (word.length > w) {
      if (cur.isNotEmpty) {
        out.add(cur);
        cur = '';
      }
      out.add(word.substring(0, w));
      word = word.substring(w);
    }
    if (cur.isEmpty) {
      cur = word;
    } else if (cur.length + 1 + word.length <= w) {
      cur = '$cur $word';
    } else {
      out.add(cur);
      cur = word;
    }
  }
  if (cur.isNotEmpty) out.add(cur);
  return out;
}

String _row(String l, String r, int cols) {
  final left = _ascii(l);
  final right = _ascii(r);
  final space = cols - right.length - 1;
  final lt = left.length > space ? left.substring(0, space < 0 ? 0 : space) : left;
  return lt.padRight(cols - right.length) + right;
}

/// Baris teks struk. Dipakai oleh cetak ESC/POS dan uji lebar kolom.
/// Tiap elemen: (teks, rata) dengan rata 'c' tengah, 'l' kiri, 'b' tebal-tengah.
List<(String, String)> receiptLines(Txn t, ReceiptOptions o) {
  final w = o.cols;
  final rule = ''.padRight(w, '-');
  final out = <(String, String)>[
    for (final l in _wrap(o.businessName.toUpperCase(), w)) (l, 'b'),
    if (o.branchName.isNotEmpty) for (final l in _wrap(o.branchName, w)) (l, 'c'),
    (rule, 'l'),
    (_row('No', t.id, w), 'l'),
    (_row('Tanggal', '${tanggal(t.time)} ${hhmm(t.time)}', w), 'l'),
    if (o.showCashier && t.cashierName.isNotEmpty) (_row('Kasir', t.cashierName, w), 'l'),
    (rule, 'l'),
  ];
  for (final l in t.lines) {
    for (final n in _wrap(l.name, w)) {
      out.add((n, 'l'));
    }
    out.add((_row('  ${l.qty} x ${rupiah(l.unitPrice)}', rupiah(l.gross), w), 'l'));
    if (l.discount.isNone == false) {
      out.add((_row('  Diskon item', rupiah(-l.priced.discountAmount), w), 'l'));
    }
  }
  out.add((rule, 'l'));
  out.add((_row('Subtotal', rupiah(t.subtotal), w), 'l'));
  if (t.itemDiscount > 0) out.add((_row('Diskon item', rupiah(-t.itemDiscount), w), 'l'));
  if (t.totals.txnDiscount > 0) {
    out.add((_row('Diskon transaksi', rupiah(-t.totals.txnDiscount), w), 'l'));
  }
  if (t.tax > 0) {
    out.add((_row('Pajak (${(t.taxBps / 100).toStringAsFixed(t.taxBps % 100 == 0 ? 0 : 2)}%)', rupiah(t.tax), w), 'l'));
  }
  out.add((_row('TOTAL', rupiah(t.total), w), 'l'));
  if (t.method == PayMethod.cash) {
    out.add((_row('Tunai', rupiah(t.paid), w), 'l'));
    out.add((_row('Kembalian', rupiah(t.change), w), 'l'));
  } else {
    out.add((_row('Metode', 'QRIS', w), 'l'));
  }
  if (t.status != TxnStatus.paid) {
    out.add((_row('Status', t.status == TxnStatus.voided ? 'VOID' : 'RETUR', w), 'l'));
  }
  if (t.note.isNotEmpty) {
    out.add((rule, 'l'));
    for (final n in _wrap('Catatan: ${t.note}', w)) {
      out.add((n, 'l'));
    }
  }
  out.add((rule, 'l'));
  for (final n in _wrap(o.footer, w)) {
    out.add((n, 'c'));
  }
  return out;
}

/// Perintah ESC/POS siap kirim ke printer thermal Bluetooth.
Uint8List buildEscPos(Txn t, ReceiptOptions o) => _escpos(receiptLines(t, o), o);

/// Halaman uji cetak.
Uint8List buildTestPage(ReceiptOptions o) => _escpos([
      (_ascii(o.businessName.toUpperCase()), 'b'),
      (''.padRight(o.cols, '-'), 'l'),
      ('Halaman uji cetak', 'c'),
      ('Kertas ${o.paperMm} mm (${o.cols} kolom)', 'c'),
      (''.padRight(o.cols, '1234567890').substring(0, o.cols), 'l'),
    ], o);

Uint8List _escpos(List<(String, String)> lines, ReceiptOptions o) {
  final b = BytesBuilder();
  b.add([0x1B, 0x40]); // reset
  for (final (text, align) in lines) {
    b.add([0x1B, 0x61, align == 'l' ? 0 : 1]); // rata kiri / tengah
    b.add([0x1B, 0x45, align == 'b' ? 1 : 0]); // tebal
    b.add(ascii.encode(text));
    b.add([0x0A]);
  }
  b.add([0x1B, 0x45, 0]);
  b.add([0x1B, 0x64, 4]); // feed 4 baris
  b.add([0x1D, 0x56, 0x42, 0x00]); // potong (diabaikan printer tanpa cutter)
  return b.toBytes();
}

/// Struk PDF, cadangan bila printer tidak tersedia (dibagikan lewat share sheet).
Future<Uint8List> buildReceiptPdf(Txn t, ReceiptOptions o) async {
  final doc = pw.Document();
  final width = (o.paperMm >= 80 ? 80 : 58) * PdfPageFormat.mm;
  final lines = receiptLines(t, o);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat(width, double.infinity, marginAll: 4 * PdfPageFormat.mm),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final (text, align) in lines)
          pw.Text(text,
              textAlign: align == 'l' ? pw.TextAlign.left : pw.TextAlign.center,
              style: pw.TextStyle(
                  font: pw.Font.courier(),
                  fontBold: pw.Font.courierBold(),
                  fontSize: o.paperMm >= 80 ? 8 : 7,
                  fontWeight: align == 'b' ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    ),
  ));
  return doc.save();
}

/// Laporan shift untuk dicetak.
Uint8List buildShiftReport(Shift s, ReceiptOptions o) {
  final w = o.cols;
  final rule = ''.padRight(w, '-');
  return _escpos([
    (_ascii(o.businessName.toUpperCase()), 'b'),
    ('LAPORAN SHIFT', 'c'),
    (rule, 'l'),
    (_row('Kasir', s.cashierName, w), 'l'),
    (_row('Mulai', '${tanggal(s.openedAt)} ${hhmm(s.openedAt)}', w), 'l'),
    if (s.closedAt != null) (_row('Selesai', '${tanggal(s.closedAt!)} ${hhmm(s.closedAt!)}', w), 'l'),
    (rule, 'l'),
    (_row('Transaksi', '${s.txnCount}', w), 'l'),
    (_row('Penjualan tunai', rupiah(s.cashSales), w), 'l'),
    (_row('Penjualan QRIS', rupiah(s.qrisSales), w), 'l'),
    (_row('Retur tunai', rupiah(-s.cashRefunds), w), 'l'),
    (_row('Total', rupiah(s.salesTotal), w), 'l'),
    (rule, 'l'),
    (_row('Kas awal', rupiah(s.openingCash), w), 'l'),
    (_row('Kas seharusnya', rupiah(s.expectedCash ?? 0), w), 'l'),
    (_row('Kas fisik', rupiah(s.closingCash ?? 0), w), 'l'),
    (_row('Selisih', rupiah(s.difference ?? 0), w), 'l'),
    if (s.note.isNotEmpty) (_ascii('Catatan: ${s.note}'), 'l'),
  ], o);
}

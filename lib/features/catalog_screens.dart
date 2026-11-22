import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/pricing.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/app_state.dart';

/// M13 - Katalog kasir (membaca dari database lokal; tanpa internet)
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _cat = 'Semua';
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final cats = ['Semua', ...s.categories.map((c) => c.name)];
        if (!cats.contains(_cat)) _cat = 'Semua';
        final list = s.search(_q.text, category: _cat);
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.businessName,
                              style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.6)),
                          Text('${s.branch} · Kasir ${s.cashierName.split(' ').first}',
                              style: const TextStyle(fontSize: 13, color: TK.mut)),
                        ],
                      ),
                    ),
                    TonalIconButton(Icons.history_rounded, 'Riwayat',
                        () => Navigator.pushNamed(context, Routes.history)),
                    const SizedBox(width: 8),
                    TonalIconButton(Icons.qr_code_scanner_rounded, 'Scan barcode',
                        () => Navigator.pushNamed(context, Routes.scan)),
                    const SizedBox(width: 8),
                    TonalIconButton(Icons.person_outline_rounded, 'Profil',
                        () => Navigator.pushNamed(context, Routes.profile)),
                  ]),
                ),
                _SyncBanner(s),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _q,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Cari produk atau barcode',
                      hintStyle: const TextStyle(color: TK.mut),
                      prefixIcon: const Icon(Icons.search_rounded, color: TK.mut),
                      suffixIcon: _q.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Hapus pencarian',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(_q.clear)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: TK.line)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: TK.g, width: 1.6)),
                    ),
                  ),
                ),
                SizedBox(
                  height: 64,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final c in cats)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c),
                            selected: _cat == c,
                            onSelected: (_) => setState(() => _cat = c),
                            showCheckmark: false,
                            selectedColor: TK.g,
                            backgroundColor: Colors.white,
                            side: BorderSide(color: _cat == c ? TK.g : TK.line),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22)),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            labelStyle: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: _cat == c ? Colors.white : TK.ink),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Daftar produk',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      Text('${list.length} produk',
                          style: const TextStyle(color: TK.mut, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Text(
                              s.products.isEmpty
                                  ? 'Katalog kosong. Sinkronkan saat online.'
                                  : 'Produk tidak ditemukan.',
                              style: const TextStyle(color: TK.mut)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _ProductTile(list[i].id),
                        ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: s.cartCount == 0
              ? null
              : Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  color: TK.bg,
                  child: SafeArea(
                    top: false,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TkButton(
                        'Lihat keranjang · ${s.cartCount} item   ${rupiah(s.subtotal)}',
                        trailing: Icons.arrow_forward_rounded,
                        onPressed: () => Navigator.pushNamed(context, Routes.cart),
                      ),
                      const SizedBox(height: 6),
                      Text(
                          s.lastSyncAt == null
                              ? 'Tersimpan di perangkat'
                              : 'Tersimpan di perangkat · Sinkron terakhir ${hhmm(s.lastSyncAt!)}',
                          style: const TextStyle(fontSize: 12, color: TK.mut)),
                    ]),
                  ),
                ),
        );
      },
    );
  }
}

/// Banner status sinkron. Tampil bila offline, ada antrean, atau ada masalah.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) {
    final failed = s.failedSync;
    if (s.online && s.pendingSync == 0 && failed == 0) return const SizedBox.shrink();
    final String title;
    final String body;
    final Tone tone;
    final IconData icon;
    if (failed > 0) {
      title = '$failed perlu bantuan';
      body = 'Ketuk untuk melihat masalah sinkronisasi';
      tone = Tone.bad;
      icon = Icons.error_outline_rounded;
    } else if (!s.online) {
      title = 'Offline? Tetap bisa jualan.';
      body = s.pendingSync > 0
          ? '${s.pendingSync} transaksi menunggu sinkron'
          : 'Transaksi tersimpan di perangkat';
      tone = Tone.warn;
      icon = Icons.cloud_off_rounded;
    } else {
      title = 'Menyinkronkan…';
      body = '${s.pendingSync} transaksi menunggu sinkron';
      tone = Tone.warn;
      icon = Icons.cloud_upload_outlined;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: TkBanner(title,
          body: body,
          tone: tone,
          icon: icon,
          onTap: () => Navigator.pushNamed(context, Routes.sync)),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile(this.id);
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final p = s.product(id);
    final stock = s.stock[id] ?? 0;
    final q = s.qtyOf(id);
    final low = stock <= p.minStock;
    return TkCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          if (p.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(p.imageUrl!,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                // Stok lokal habis tidak memblokir penjualan (BR-06).
                Text(
                    stock <= 0
                        ? '${p.category} · Stok lokal habis (tetap bisa dijual)'
                        : '${p.category} · Stok lokal $stock',
                    style: TextStyle(fontSize: 13, color: low ? TK.warn : TK.mut)),
                const SizedBox(height: 6),
                Price(p.price, size: 16, color: TK.g),
              ],
            ),
          ),
          if (q == 0)
            Tooltip(
              message: 'Tambah ${p.name}',
              child: Material(
                color: TK.g50,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => s.add(id),
                  child: const SizedBox(
                      width: 52, height: 52, child: Icon(Icons.add, color: TK.gd)),
                ),
              ),
            )
          else
            QtyStepper(qty: q, onMinus: () => s.add(id, -1), onPlus: () => s.add(id)),
        ],
      ),
    );
  }
}

/// Dialog diskon: nominal rupiah atau persen.
Future<Discount?> pickDiscount(BuildContext context, Discount current,
    {String title = 'Diskon'}) {
  var percent = current.percent;
  final c = TextEditingController(text: current.value > 0 ? '${current.value}' : '');
  return showDialog<Discount>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TkSegmented<bool>(
            options: const [(false, 'Rp'), (true, '%')],
            value: percent,
            onChanged: (v) => set(() => percent = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                prefixText: percent ? null : 'Rp ', suffixText: percent ? '%' : null),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, const Discount.none()),
              child: const Text('Hapus')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(
              onPressed: () {
                final v = parseRupiah(c.text);
                Navigator.pop(ctx,
                    percent ? Discount.percent(v.clamp(0, 100)) : Discount.amount(v));
              },
              child: const Text('Terapkan')),
        ],
      ),
    ),
  );
}

/// M14 - Keranjang
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (s.cart.isEmpty) {
          return Screen(
            title: 'Keranjang',
            child: const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                  child: Text('Keranjang kosong. Pilih produk di katalog.',
                      style: TextStyle(color: TK.mut))),
            ),
          );
        }
        final t = s.totals;
        return Screen(
          title: 'Keranjang',
          bottom: Column(mainAxisSize: MainAxisSize.min, children: [
            TkButton('Lanjut ke pembayaran',
                trailing: Icons.arrow_forward_rounded,
                onPressed: () => Navigator.pushNamed(context, Routes.payment)),
            gap8,
            Text(s.online ? 'Online' : 'Offline · Pembayaran tunai tetap tersedia',
                style: const TextStyle(fontSize: 12, color: TK.mut)),
          ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pesanan baru',
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.6)),
              Text('${s.cartCount} item · ${s.branch}',
                  style: const TextStyle(color: TK.mut)),
              gap16,
              for (final e in s.cart.entries) ...[
                _CartLine(e.key, e.value),
                gap12,
              ],
              _ActionRow(
                icon: Icons.sticky_note_2_outlined,
                text: s.cartNote.isEmpty ? 'Tambah catatan pesanan' : s.cartNote,
                active: s.cartNote.isNotEmpty,
                onTap: () => _editNote(context),
              ),
              gap8,
              _ActionRow(
                icon: Icons.sell_outlined,
                text: s.txnDiscount.isNone
                    ? 'Tambah diskon transaksi'
                    : 'Diskon transaksi ${s.txnDiscount.percent ? '${s.txnDiscount.value}%' : rupiah(s.txnDiscount.value)}',
                active: !s.txnDiscount.isNone,
                onTap: () async {
                  final d = await pickDiscount(context, s.txnDiscount,
                      title: 'Diskon transaksi');
                  if (d != null) s.setTxnDiscount(d);
                },
              ),
              gap24,
              const Text('Ringkasan pembayaran',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              gap8,
              InfoRow('Subtotal', rupiah(t.subtotal)),
              if (t.itemDiscount > 0)
                InfoRow('Diskon item', rupiah(-t.itemDiscount), color: TK.g),
              InfoRow('Diskon transaksi', rupiah(-t.txnDiscount),
                  color: t.txnDiscount > 0 ? TK.g : null),
              InfoRow('Pajak (${pctLabel(s.taxBps)}%)', rupiah(t.tax)),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total bayar',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Price(t.total, size: 22),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editNote(BuildContext context) async {
    final c = TextEditingController(text: AppState.I.cartNote);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Catatan pesanan'),
        content: TextField(controller: c, autofocus: true, maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Simpan')),
        ],
      ),
    );
    if (v != null) AppState.I.setNote(v);
  }
}

/// Baris aksi bergaya kartu (catatan, diskon).
class _ActionRow extends StatelessWidget {
  const _ActionRow(
      {required this.icon, required this.text, required this.onTap, this.active = false});
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => TkCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 22, color: active ? TK.g : TK.ink),
          const SizedBox(width: 14),
          Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? TK.ink : TK.mut))),
          const Icon(Icons.chevron_right_rounded, color: TK.mut),
        ]),
      );
}

class _CartLine extends StatelessWidget {
  const _CartLine(this.id, this.qty);
  final String id;
  final int qty;
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final p = s.product(id);
    final d = s.lineDiscounts[id] ?? const Discount.none();
    final line = PriceLine(p.price, qty, d);
    return TkCard(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text('$qty × ${rupiah(p.price)}',
                  style: const TextStyle(fontSize: 13, color: TK.mut)),
              if (!d.isNone)
                Text(
                    'Diskon ${d.percent ? '${d.value}%' : rupiah(d.value)} (${rupiah(-line.discountAmount)})',
                    style: const TextStyle(fontSize: 12, color: TK.g)),
              const SizedBox(height: 8),
              Price(line.net, size: 16, color: TK.g),
              InkWell(
                onTap: () async {
                  final r = await pickDiscount(context, d, title: 'Diskon ${p.name}');
                  if (r != null) s.setLineDiscount(id, r);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(d.isNone ? 'Beri diskon item' : 'Ubah diskon item',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: TK.gd)),
                ),
              ),
            ],
          ),
        ),
        QtyStepper(qty: qty, onMinus: () => s.add(id, -1), onPlus: () => s.add(id)),
      ]),
    );
  }
}

/// Bingkai sudut hijau pada pemindai.
class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF6FD3A8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const r = 28.0, l = 44.0;
    final w = size.width, h = size.height;
    void corner(double x, double y, double dx, double dy) {
      final path = Path()
        ..moveTo(x, y + dy * l)
        ..lineTo(x, y + dy * r)
        ..quadraticBezierTo(x, y, x + dx * r, y)
        ..lineTo(x + dx * l, y);
      canvas.drawPath(path, p);
    }

    corner(0, 0, 1, 1);
    corner(w, 0, -1, 1);
    corner(0, h, 1, -1);
    corner(w, h, -1, -1);
    final line = Paint()
      ..color = const Color(0xFF6FD3A8)
      ..strokeWidth = 3;
    canvas.drawLine(Offset(w * .08, h / 2), Offset(w * .92, h / 2), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// M04 - Scan barcode dengan kamera (berfungsi tanpa internet) atau ketik manual.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _ctl = MobileScannerController(formats: const [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.qrCode,
  ]);
  String? _foundId;
  int _qty = 1;
  String? _lastCode;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _lookup(String code) {
    if (code == _lastCode && _foundId != null) return;
    _lastCode = code;
    final p = AppState.I.bySku(code);
    if (p == null) {
      toast(context, 'Kode "$code" tidak ditemukan.');
      return;
    }
    setState(() {
      _foundId = p.id;
      _qty = 1;
    });
  }

  Future<void> _manual() async {
    final c = TextEditingController();
    final sku = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ketik kode manual'),
        content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'SKU atau barcode')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Cari')),
        ],
      ),
    );
    if (sku != null && sku.trim().isNotEmpty) _lookup(sku);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final p = _foundId == null ? null : s.product(_foundId!);
    const dark = Color(0xFF0B1511);
    return Scaffold(
      backgroundColor: dark,
      appBar: AppBar(
        backgroundColor: dark,
        foregroundColor: Colors.white,
        shape: const Border(),
        title: const Text('Scan barcode',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(36),
                    child: Stack(fit: StackFit.expand, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: MobileScanner(
                          controller: _ctl,
                          onDetect: (cap) {
                            for (final b in cap.barcodes) {
                              final v = b.rawValue;
                              if (v != null && v.isNotEmpty) {
                                _lookup(v);
                                break;
                              }
                            }
                          },
                          errorBuilder: (ctx, err) => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                  'Kamera tidak tersedia. Izinkan akses kamera atau ketik kode manual.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70)),
                            ),
                          ),
                        ),
                      ),
                      const CustomPaint(painter: _ScanFramePainter()),
                    ]),
                  ),
                ),
              ),
            ),
            const Text('Arahkan kamera ke barcode produk.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Berfungsi tanpa internet.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _DarkChipButton(Icons.flashlight_on_outlined, 'Senter', () => _ctl.toggleTorch()),
              const SizedBox(width: 10),
              _DarkChipButton(Icons.keyboard_alt_outlined, 'Ketik kode manual', _manual),
            ]),
            const SizedBox(height: 12),
            if (p != null)
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const IconTile(Icons.check_rounded, size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Produk ditemukan · ${p.sku}',
                                style: const TextStyle(
                                    color: TK.mut, fontSize: 13)),
                            Text(p.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 17)),
                          ],
                        ),
                      ),
                      Price(p.price, size: 17),
                    ]),
                    gap12,
                    Row(children: [
                      QtyStepper(
                          qty: _qty,
                          onMinus: _qty > 1 ? () => setState(() => _qty--) : null,
                          onPlus: () => setState(() => _qty++)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TkButton('Tambah ke keranjang', onPressed: () {
                          s.add(p.id, _qty);
                          toast(context, '${p.name} ditambahkan.');
                          setState(() {
                            _foundId = null;
                            _lastCode = null;
                          });
                        }),
                      ),
                    ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DarkChipButton extends StatelessWidget {
  const _DarkChipButton(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF2B3732),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            ]),
          ),
        ),
      );
}

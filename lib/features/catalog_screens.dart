import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/pricing.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/app_state.dart';
import '../data/models.dart';

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
          appBar: AppBar(
            toolbarHeight: 64,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.businessName),
                Text('${s.branch} · Kasir ${s.cashierName.split(' ').first}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500, color: TK.mut)),
              ],
            ),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                  tooltip: 'Scan barcode',
                  onPressed: () => Navigator.pushNamed(context, Routes.scan),
                  icon: const Icon(Icons.qr_code_scanner_rounded)),
              IconButton(
                  tooltip: 'Riwayat',
                  onPressed: () => Navigator.pushNamed(context, Routes.history),
                  icon: const Icon(Icons.receipt_long_rounded)),
              IconButton(
                  tooltip: 'Profil',
                  onPressed: () => Navigator.pushNamed(context, Routes.profile),
                  icon: const Icon(Icons.person_outline_rounded)),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _SyncStrip(s),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _q,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Cari nama, SKU, atau barcode',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _q.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Hapus pencarian',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(_q.clear)),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  height: 60,
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
                                borderRadius: BorderRadius.circular(18)),
                            labelStyle: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
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
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _ProductTile(list[i].id),
                        ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: s.cartCount == 0
              ? null
              : Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: TK.line))),
                  child: SafeArea(
                    top: false,
                    child: TkButton(
                      'Lihat keranjang · ${s.cartCount} item   ${rupiah(s.subtotal)}',
                      icon: Icons.shopping_bag_outlined,
                      onPressed: () => Navigator.pushNamed(context, Routes.cart),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Indikator koneksi, antrean, dan sinkron terakhir.
class _SyncStrip extends StatelessWidget {
  const _SyncStrip(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) {
    final online = s.online;
    final last = s.lastSyncAt;
    final failed = s.failedSync;
    final tone = failed > 0 ? TK.bad : (online ? TK.gd : TK.warn);
    return InkWell(
      onTap: () => Navigator.pushNamed(context, Routes.sync),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: failed > 0
            ? TK.bad.withValues(alpha: .08)
            : (online ? TK.g50 : TK.warn.withValues(alpha: .12)),
        child: Row(children: [
          Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off_rounded,
              size: 18, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                online ? 'Online' : 'Offline · tetap bisa jualan',
                if (s.pendingSync > 0) '${s.pendingSync} menunggu sinkron',
                if (failed > 0) '$failed perlu bantuan',
                if (last != null && s.pendingSync == 0 && failed == 0)
                  'Sinkron ${hhmm(last)}',
              ].join(' · '),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: tone),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: tone),
        ]),
      ),
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
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: TK.g50, borderRadius: BorderRadius.circular(12)),
            child: p.imageUrl == null
                ? _icon(p)
                : Image.network(p.imageUrl!,
                    fit: BoxFit.cover, errorBuilder: (_, __, ___) => _icon(p)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                // Stok lokal habis tidak memblokir penjualan (BR-06).
                Text(
                    stock <= 0
                        ? '${p.category} · Stok lokal habis (tetap bisa dijual)'
                        : '${p.category} · Stok lokal $stock',
                    style: TextStyle(fontSize: 12, color: low ? TK.warn : TK.mut)),
                const SizedBox(height: 4),
                Price(p.price),
              ],
            ),
          ),
          if (q == 0)
            IconButton.filledTonal(
              tooltip: 'Tambah ${p.name}',
              onPressed: () => s.add(id),
              icon: const Icon(Icons.add),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              style: IconButton.styleFrom(
                  backgroundColor: TK.g50, foregroundColor: TK.gd),
            )
          else
            QtyStepper(qty: q, onMinus: () => s.add(id, -1), onPlus: () => s.add(id)),
        ],
      ),
    );
  }

  Widget _icon(Product p) => Icon(
      p.category == 'Makanan' ? Icons.bakery_dining_rounded : Icons.local_cafe_rounded,
      color: TK.g);
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
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Rp')),
              ButtonSegment(value: true, label: Text('%')),
            ],
            selected: {percent},
            onSelectionChanged: (v) => set(() => percent = v.first),
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
                icon: Icons.arrow_forward_rounded,
                onPressed: () => Navigator.pushNamed(context, Routes.payment)),
            gap8,
            Text(s.online ? 'Online' : 'Offline · Pembayaran tunai tetap tersedia',
                style: const TextStyle(fontSize: 12, color: TK.mut)),
          ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pesanan baru',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              Text('${s.cartCount} item · ${s.branch}',
                  style: const TextStyle(color: TK.mut)),
              gap16,
              for (final e in s.cart.entries) ...[
                _CartLine(e.key, e.value),
                gap8,
              ],
              Row(children: [
                Expanded(
                  child: TkButton(
                      s.cartNote.isEmpty ? 'Catatan pesanan' : 'Ubah catatan',
                      kind: BtnKind.outline,
                      small: true,
                      icon: Icons.edit_note_rounded,
                      onPressed: () => _editNote(context)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TkButton(
                      s.txnDiscount.isNone ? 'Diskon transaksi' : 'Ubah diskon',
                      kind: BtnKind.outline,
                      small: true,
                      icon: Icons.sell_outlined,
                      onPressed: () async {
                        final d = await pickDiscount(context, s.txnDiscount,
                            title: 'Diskon transaksi');
                        if (d != null) s.setTxnDiscount(d);
                      }),
                ),
              ]),
              if (s.cartNote.isNotEmpty) ...[
                gap8,
                Text('Catatan: ${s.cartNote}',
                    style: const TextStyle(fontSize: 13, color: TK.mut)),
              ],
              gap24,
              const Cap('Ringkasan pembayaran'),
              TkCard(
                child: Column(children: [
                  InfoRow('Subtotal', rupiah(t.subtotal)),
                  InfoRow('Diskon item',
                      t.itemDiscount > 0 ? rupiah(-t.itemDiscount) : 'Rp0'),
                  InfoRow('Diskon transaksi',
                      t.txnDiscount > 0 ? rupiah(-t.txnDiscount) : 'Rp0'),
                  InfoRow('Pajak (${pctLabel(s.taxBps)}%)', rupiah(t.tax)),
                  const Divider(height: 20),
                  InfoRow('Total bayar', rupiah(t.total), bold: true),
                ]),
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
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('$qty × ${rupiah(p.price)}',
                  style: const TextStyle(fontSize: 13, color: TK.mut)),
              if (!d.isNone)
                Text(
                    'Diskon ${d.percent ? '${d.value}%' : rupiah(d.value)} (${rupiah(-line.discountAmount)})',
                    style: const TextStyle(fontSize: 12, color: TK.gd)),
              const SizedBox(height: 4),
              Row(children: [
                Price(line.net),
                TextButton(
                  onPressed: () async {
                    final r = await pickDiscount(context, d, title: 'Diskon ${p.name}');
                    if (r != null) s.setLineDiscount(id, r);
                  },
                  child: Text(d.isNone ? 'Beri diskon' : 'Ubah diskon'),
                ),
              ]),
            ],
          ),
        ),
        QtyStepper(qty: qty, onMinus: () => s.add(id, -1), onPlus: () => s.add(id)),
      ]),
    );
  }
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
    return Scaffold(
      backgroundColor: const Color(0xFF0B1511),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1511),
        foregroundColor: Colors.white,
        shape: const Border(),
        title: const Text('Scan barcode',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
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
              ),
            ),
            const Text('Arahkan kamera ke barcode produk.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Berfungsi tanpa internet.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: TkButton('Senter',
                      kind: BtnKind.outline,
                      small: true,
                      icon: Icons.flashlight_on_outlined,
                      onPressed: () => _ctl.toggleTorch()),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TkButton('Ketik kode manual',
                      kind: BtnKind.outline,
                      small: true,
                      icon: Icons.keyboard_alt_outlined,
                      onPressed: _manual),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            if (p != null)
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Produk ditemukan · ${p.sku}',
                        style: const TextStyle(
                            color: TK.gd, fontSize: 12, fontWeight: FontWeight.w700)),
                    gap8,
                    Row(children: [
                      Expanded(
                          child: Text(p.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16))),
                      Price(p.price, size: 16),
                    ]),
                    gap12,
                    Row(children: [
                      QtyStepper(
                          qty: _qty,
                          onMinus: _qty > 1 ? () => setState(() => _qty--) : null,
                          onPlus: () => setState(() => _qty++)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TkButton('Tambah ke keranjang', small: true, onPressed: () {
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

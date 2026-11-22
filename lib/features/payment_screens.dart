import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/printer_service.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/app_state.dart';
import '../data/backend.dart';
import '../data/models.dart';

/// Kartu total bayar hijau muda (pembayaran dan QRIS).
class _TotalCard extends StatelessWidget {
  const _TotalCard(this.total, this.itemCount);
  final int total;
  final int itemCount;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration:
            BoxDecoration(color: TK.g50, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TOTAL BAYAR',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .8, color: TK.gd)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Price(total, size: 40, color: TK.gd)),
            Text('$itemCount item',
                style: const TextStyle(fontSize: 14, color: TK.mut)),
          ]),
        ]),
      );
}

class _MethodTile extends StatelessWidget {
  const _MethodTile(this.icon, this.label, this.selected, this.dim, this.onTap);
  final IconData icon;
  final String label;
  final bool selected;
  final bool dim;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: selected ? TK.g50 : TK.neutralBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? TK.g : Colors.transparent, width: 1.6),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: selected ? TK.gd : (dim ? TK.mut.withValues(alpha: .6) : TK.ink)),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: selected ? TK.gd : (dim ? TK.mut.withValues(alpha: .7) : TK.ink))),
            ]),
          ),
        ),
      );
}

/// M15 - Pembayaran tunai
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _recv = TextEditingController();
  PayMethod _method = PayMethod.cash;
  bool _busy = false;

  Future<void> _payCash(int received) async {
    setState(() => _busy = true);
    try {
      final t = await AppState.I.checkout(PayMethod.cash, received);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, Routes.success, arguments: t.id);
    } on BusinessRuleException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chip(String label, int amount, int received) {
    final sel = received == amount && received > 0;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _recv.text = '$amount'),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: sel ? TK.g : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: sel ? TK.g : TK.line),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : TK.ink)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final total = s.total;
    final received = parseRupiah(_recv.text);
    final change = received - total;
    final canPay = _method == PayMethod.cash ? received >= total : true;

    return Screen(
      title: 'Pembayaran',
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        TkButton(
          _method == PayMethod.cash ? 'Selesaikan pembayaran' : 'Tampilkan QRIS',
          trailing: Icons.arrow_forward_rounded,
          onPressed: !canPay || _busy
              ? null
              : () {
                  if (_method == PayMethod.qris) {
                    Navigator.pushNamed(context, Routes.qris);
                    return;
                  }
                  _payCash(received);
                },
        ),
        gap8,
        const Text('Pastikan uang tunai sudah diterima.',
            style: TextStyle(fontSize: 12, color: TK.mut)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TotalCard(total, s.cartCount),
          gap24,
          const Text('Metode pembayaran',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          gap12,
          Row(children: [
            Expanded(
              child: _MethodTile(Icons.payments_outlined, 'Tunai',
                  _method == PayMethod.cash, false,
                  () => setState(() => _method = PayMethod.cash)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MethodTile(Icons.qr_code_2_rounded, 'QRIS',
                  _method == PayMethod.qris, !s.online,
                  () => setState(() => _method = PayMethod.qris)),
            ),
          ]),
          gap8,
          GestureDetector(
            onTap: () => setState(() => _method = PayMethod.qris),
            child: Text.rich(TextSpan(
              style: const TextStyle(fontSize: 13, color: TK.mut),
              children: [
                const TextSpan(text: 'QRIS memerlukan koneksi internet. '),
                if (!s.online)
                  const TextSpan(
                      text: 'Lihat alur QRIS saat online',
                      style: TextStyle(color: TK.gd, fontWeight: FontWeight.w700)),
              ],
            )),
          ),
          gap16,
          if (_method == PayMethod.qris)
            const TkBanner('QR dibuat di layar berikutnya.',
                body: 'Jika offline, gunakan pembayaran tunai.',
                icon: Icons.wifi_rounded,
                tone: Tone.ok)
          else ...[
            TkField(
              label: 'Uang diterima',
              controller: _recv,
              prefix: 'Rp ',
              digitsOnly: true,
              keyboard: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            gap12,
            Row(children: [
              _chip('Uang pas', total, received),
              _chip('Rp50.000', 50000, received),
              _chip('Rp100.000', 100000, received),
            ]),
            gap16,
            TkCard(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Kembalian',
                    style: TextStyle(fontSize: 14, color: TK.mut)),
                const SizedBox(height: 4),
                Price(received >= total ? change : 0, size: 34, color: TK.gd),
              ]),
            ),
            gap12,
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.cloud_off_rounded, size: 18, color: TK.mut),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Disimpan lokal, lalu disinkronkan otomatis saat internet kembali.',
                    style: TextStyle(fontSize: 13, color: TK.mut)),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

enum _QrPhase { creating, waiting, expired, offline, error }

/// M05 - Pembayaran QRIS dinamis. QR dibuat per transaksi; status menjadi lunas
/// setelah webhook gateway terverifikasi di server (BR-10), yang di sini
/// dibaca lewat polling status tagihan.
class QrisScreen extends StatefulWidget {
  const QrisScreen({super.key});
  @override
  State<QrisScreen> createState() => _QrisScreenState();
}

class _QrisScreenState extends State<QrisScreen> {
  // UUID pesanan dibuat sekali; semua percobaan memakai UUID yang sama (BR-05).
  late final String _orderUuid = AppState.I.newUuid();
  late final int _amount = AppState.I.total;
  QrisCharge? _charge;
  _QrPhase _phase = _QrPhase.creating;
  String? _error;
  Timer? _tick;
  Timer? _poll;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _create();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final c = _charge;
      if (_phase == _QrPhase.waiting && c != null && !DateTime.now().isBefore(c.expiresAt)) {
        setState(() => _phase = _QrPhase.expired); // QR kedaluwarsa ditandai
      } else {
        setState(() {});
      }
    });
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _phase = _QrPhase.creating;
      _error = null;
    });
    final gw = AppState.I.gateway;
    try {
      if (gw == null) throw const SyncException('Gateway belum dikonfigurasi');
      final c = await gw.createQris(orderUuid: _orderUuid, amount: _amount);
      if (!mounted) return;
      setState(() {
        _charge = c;
        _phase = _QrPhase.waiting;
      });
    } on SyncException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = e.permanent ? _QrPhase.error : _QrPhase.offline;
      });
    }
  }

  Future<void> _check() async {
    final c = _charge;
    if (c == null || _phase != _QrPhase.waiting || _finishing) return;
    try {
      final st = await AppState.I.gateway!.status(c.id);
      if (!mounted) return;
      if (st == QrisState.paid) {
        await _finish(paymentRef: c.id);
      } else if (st == QrisState.expired) {
        setState(() => _phase = _QrPhase.expired);
      }
    } on SyncException {
      // Gangguan sesaat: coba lagi pada putaran berikutnya.
    }
  }

  Future<void> _finish({String? paymentRef, bool reconcile = false}) async {
    if (_finishing) return;
    _finishing = true;
    try {
      final t = await AppState.I.checkout(PayMethod.qris, 0,
          uuid: _orderUuid, paymentRef: paymentRef, reconcile: reconcile);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
          context, Routes.success, (r) => r.settings.name == Routes.catalog,
          arguments: t.id);
    } on BusinessRuleException catch (e) {
      _finishing = false;
      if (mounted) toast(context, e.message);
    }
  }

  /// Pelanggan sudah membayar tetapi aplikasi offline: catat dan tandai untuk
  /// rekonsiliasi saat webhook dan transaksi bertemu.
  Future<void> _markPaidOffline() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pembayaran sudah diterima?'),
        content: const Text(
            'Pastikan pelanggan menunjukkan bukti pembayaran berhasil. Transaksi ditandai untuk rekonsiliasi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya, sudah')),
        ],
      ),
    );
    if (ok == true) await _finish(reconcile: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final c = _charge;
    final left = c == null ? 0 : c.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 99999);
    final mm = (left ~/ 60).toString().padLeft(2, '0');
    final ss = (left % 60).toString().padLeft(2, '0');
    return Screen(
      title: 'Pembayaran QRIS',
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_phase == _QrPhase.expired || _phase == _QrPhase.offline || _phase == _QrPhase.error)
          TkButton('Buat QR baru', icon: Icons.refresh_rounded, onPressed: _create)
        else
          TkButton('Cek status pembayaran',
              onPressed: _phase == _QrPhase.waiting ? _check : null),
        if (_phase == _QrPhase.offline) ...[
          gap8,
          TkButton('Pelanggan sudah bayar (tandai rekonsiliasi)',
              kind: BtnKind.soft, onPressed: _markPaidOffline),
        ],
        gap8,
        TkButton('Ganti ke tunai',
            kind: BtnKind.outline, onPressed: () => Navigator.pop(context)),
        gap8,
        const Text('Status berubah otomatis saat pembayaran diterima',
            style: TextStyle(fontSize: 12, color: TK.mut)),
      ]),
      child: Column(
        children: [
          _TotalCard(_amount, s.cartCount),
          gap16,
          TkCard(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('QRIS',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('${s.businessName} · ${s.branch}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: TK.mut, fontSize: 14)),
                ),
              ]),
              gap16,
              Container(
                width: 230,
                height: 230,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: TK.line),
                ),
                child: switch (_phase) {
                  _QrPhase.creating =>
                    const Center(child: CircularProgressIndicator(color: TK.g)),
                  _QrPhase.waiting || _QrPhase.expired when c != null => Opacity(
                      opacity: _phase == _QrPhase.expired ? .25 : 1,
                      child: QrImageView(
                          data: c.qrString,
                          padding: EdgeInsets.zero,
                          eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square, color: Color(0xFF12241E)),
                          dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF12241E))),
                    ),
                  _ => const Center(
                      child: Icon(Icons.qr_code_2_rounded, size: 96, color: TK.line)),
                },
              ),
              gap16,
              if (_phase == _QrPhase.waiting)
                TkBadge('Berlaku $mm:$ss',
                    tone: Tone.warn, icon: Icons.schedule_rounded)
              else if (_phase == _QrPhase.expired)
                const TkBadge('Kedaluwarsa', tone: Tone.bad, icon: Icons.timer_off_outlined),
            ]),
          ),
          gap16,
          switch (_phase) {
            _QrPhase.waiting => const TkBanner('Menunggu pembayaran…',
                body: 'Pelanggan memindai dengan aplikasi bank atau e-wallet apa pun.',
                tone: Tone.ok,
                icon: Icons.check_rounded),
            _QrPhase.expired => const TkBanner('QR kedaluwarsa',
                body: 'Buat QR baru untuk transaksi yang sama.',
                tone: Tone.bad,
                icon: Icons.timer_off_outlined),
            _QrPhase.offline => TkBanner('QRIS butuh internet',
                body: '${_error ?? ''} Gunakan tunai, atau tandai bila pelanggan sudah membayar.',
                icon: Icons.wifi_off_rounded),
            _QrPhase.error => TkBanner('QR gagal dibuat',
                body: _error ?? '', tone: Tone.bad, icon: Icons.error_outline_rounded),
            _QrPhase.creating => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

/// M16 - Pembayaran berhasil + struk
class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key, required this.txnId});
  final String txnId;
  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  @override
  void initState() {
    super.initState();
    final p = PrinterService.I;
    if (p.autoPrint && p.device != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _print(quiet: true));
    }
  }

  Future<void> _print({bool quiet = false}) async {
    final s = AppState.I;
    final ok = await PrinterService.I.printReceipt(s.txn(widget.txnId), s.businessName, s.branch);
    if (!mounted) return;
    if (!ok && !(quiet && PrinterService.I.device == null)) {
      toast(context, '${PrinterService.I.lastError ?? 'Gagal mencetak.'} Anda bisa membagikan struk PDF.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final t = s.txn(widget.txnId);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ListenableBuilder(
            listenable: s,
            builder: (context, _) => Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(
                    child: Text(s.businessName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(s.branch,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: TK.mut)),
                  ),
                ]),
                gap24,
                Container(
                  width: 112,
                  height: 112,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: TK.g50),
                  child: const Icon(Icons.check_rounded, color: TK.gd, size: 56),
                ),
                gap16,
                const Text('Pembayaran berhasil',
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                const SizedBox(height: 4),
                const Text('Transaksi aman tersimpan di perangkat.',
                    style: TextStyle(color: TK.mut)),
                gap24,
                ReceiptCard(txn: t),
                gap12,
                if (t.needsReconcile) ...[
                  const TkBanner('Menunggu rekonsiliasi QRIS',
                      body: 'Dicatat saat offline; akan dicocokkan dengan webhook pembayaran.',
                      icon: Icons.sync_problem_rounded),
                  gap12,
                ],
                if (s.pendingSync > 0) ...[
                  TkBanner('${s.pendingSync} transaksi menunggu sinkron',
                      body: 'Akan terkirim saat internet kembali.',
                      icon: Icons.schedule_rounded,
                      onTap: () => Navigator.pushNamed(context, Routes.sync)),
                  gap12,
                ],
                Row(children: [
                  Expanded(
                      child: TkButton('Cetak struk',
                          kind: BtnKind.soft,
                          icon: Icons.print_outlined,
                          onPressed: _print)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TkButton('Bagikan',
                          kind: BtnKind.soft,
                          icon: Icons.ios_share_rounded,
                          onPressed: () =>
                              PrinterService.I.sharePdf(t, s.businessName, s.branch))),
                ]),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        color: TK.bg,
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TkButton('Transaksi baru',
                trailing: Icons.arrow_forward_rounded,
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, Routes.catalog, (r) => false)),
            gap8,
            const Text('Struk tetap bisa dicetak tanpa internet.',
                style: TextStyle(fontSize: 12, color: TK.mut)),
          ]),
        ),
      ),
    );
  }
}

/// Kartu struk, dipakai di M16 dan M07. Memakai snapshot nama dan harga (BR-04).
/// [detail] = tajuk rata kiri-kanan seperti layar detail transaksi.
class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.txn, this.detail = false});
  final Txn txn;
  final bool detail;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return TkCard(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        if (detail)
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(s.businessName,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Flexible(
              child: Text(
                  '${s.branch} · Kasir ${(txn.cashierName.isEmpty ? s.cashierName : txn.cashierName).split(' ').first}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: TK.mut, fontSize: 13)),
            ),
          ])
        else ...[
          Text(s.businessName.toUpperCase(),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 16)),
          Text('#${txn.id} · ${tanggal(txn.time)}, ${hhmm(txn.time)}',
              style: const TextStyle(fontSize: 13, color: TK.mut)),
        ],
        const Divider(height: 24),
        for (final l in txn.lines) ...[
          InfoRow('${l.qty}× ${l.name}', rupiah(l.gross)),
          if (!l.discount.isNone)
            InfoRow('   Diskon item', rupiah(-l.priced.discountAmount), color: TK.g),
        ],
        if (txn.totals.txnDiscount > 0)
          InfoRow('Diskon transaksi', rupiah(-txn.totals.txnDiscount), color: TK.g),
        if (txn.tax > 0) InfoRow('Pajak (${pctLabel(txn.taxBps)}%)', rupiah(txn.tax)),
        const Divider(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Flexible(
            child: Text('Total bayar',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          Price(txn.total, size: 22),
        ]),
        const SizedBox(height: 8),
        if (txn.method == PayMethod.cash)
          InfoRow('Tunai / Kembalian', '${rupiah(txn.paid)} / ${rupiah(txn.change)}')
        else
          const InfoRow('Metode', 'QRIS'),
        if (txn.note.isNotEmpty) InfoRow('Catatan', txn.note),
      ]),
    );
  }
}

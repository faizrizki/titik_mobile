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

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final total = s.total;
    final received = parseRupiah(_recv.text);
    final change = received - total;
    final canPay = _method == PayMethod.cash ? received >= total : true;

    return Screen(
      title: _method == PayMethod.cash ? 'Pembayaran tunai' : 'Pembayaran',
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        TkButton(
          _method == PayMethod.cash ? 'Selesaikan pembayaran' : 'Tampilkan QRIS',
          icon: Icons.check_rounded,
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
          TkCard(
            color: TK.g50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Total bayar',
                      style: TextStyle(color: TK.gd, fontWeight: FontWeight.w600)),
                  Price(total, size: 28, color: TK.gd),
                ]),
                TkBadge('${s.cartCount} item'),
              ],
            ),
          ),
          gap24,
          const Cap('Metode pembayaran'),
          Row(children: [
            Expanded(
              child: TkButton('Tunai',
                  kind: _method == PayMethod.cash ? BtnKind.primary : BtnKind.outline,
                  icon: Icons.payments_outlined,
                  onPressed: () => setState(() => _method = PayMethod.cash)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TkButton('QRIS',
                  kind: _method == PayMethod.qris ? BtnKind.primary : BtnKind.outline,
                  icon: Icons.qr_code_2_rounded,
                  onPressed: () => setState(() => _method = PayMethod.qris)),
            ),
          ]),
          gap16,
          if (_method == PayMethod.qris)
            const TkBanner('QRIS memerlukan koneksi internet.',
                body: 'Jika offline, gunakan pembayaran tunai.',
                icon: Icons.wifi_rounded)
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
              Expanded(
                child: TkButton('Uang pas',
                    kind: BtnKind.outline,
                    small: true,
                    onPressed: () => setState(() => _recv.text = '$total')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TkButton('Rp50.000',
                    kind: BtnKind.outline,
                    small: true,
                    onPressed: () => setState(() => _recv.text = '50000')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TkButton('Rp100.000',
                    kind: BtnKind.outline,
                    small: true,
                    onPressed: () => setState(() => _recv.text = '100000')),
              ),
            ]),
            gap16,
            TkCard(
              child: InfoRow('Kembalian', received >= total ? rupiah(change) : '—',
                  bold: true),
            ),
            gap12,
            const Text(
                'Disimpan lokal, lalu disinkronkan otomatis saat internet kembali.',
                style: TextStyle(fontSize: 12, color: TK.mut)),
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
              icon: Icons.refresh_rounded,
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
          const Text('Total bayar', style: TextStyle(color: TK.mut)),
          Price(_amount, size: 32),
          Text('${s.cartCount} item', style: const TextStyle(color: TK.mut)),
          gap16,
          TkCard(
            child: Column(children: [
              const Text('QRIS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text('${s.businessName} · ${s.branch}',
                  style: const TextStyle(color: TK.mut, fontSize: 13)),
              gap12,
              SizedBox(
                width: 200,
                height: 200,
                child: switch (_phase) {
                  _QrPhase.creating =>
                    const Center(child: CircularProgressIndicator(color: TK.g)),
                  _QrPhase.waiting || _QrPhase.expired when c != null => Opacity(
                      opacity: _phase == _QrPhase.expired ? .25 : 1,
                      child: QrImageView(data: c.qrString, size: 200, padding: EdgeInsets.zero),
                    ),
                  _ => const Center(
                      child: Icon(Icons.qr_code_2_rounded, size: 96, color: TK.line)),
                },
              ),
              gap12,
              if (_phase == _QrPhase.waiting)
                TkBadge('Berlaku $mm:$ss', tone: Tone.warn)
              else if (_phase == _QrPhase.expired)
                const TkBadge('Kedaluwarsa', tone: Tone.bad),
            ]),
          ),
          gap16,
          switch (_phase) {
            _QrPhase.waiting => const TkBanner('Menunggu pembayaran…',
                body: 'Pelanggan memindai dengan aplikasi bank atau e-wallet apa pun.',
                tone: Tone.ok,
                icon: Icons.hourglass_bottom_rounded),
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
    return Screen(
      title: 'Pembayaran berhasil',
      showBack: false,
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        TkButton('Transaksi baru',
            icon: Icons.add_rounded,
            onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context, Routes.catalog, (r) => false)),
        gap8,
        const Text('Struk tetap bisa dicetak tanpa internet.',
            style: TextStyle(fontSize: 12, color: TK.mut)),
      ]),
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) => Column(
          children: [
            const Icon(Icons.check_circle_rounded, color: TK.g, size: 64),
            gap8,
            const Text('Pembayaran berhasil',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const Text('Transaksi aman tersimpan di perangkat.',
                style: TextStyle(color: TK.mut)),
            gap16,
            ReceiptCard(txn: t),
            gap12,
            if (t.needsReconcile)
              const TkBanner('Menunggu rekonsiliasi QRIS',
                  body: 'Dicatat saat offline; akan dicocokkan dengan webhook pembayaran.',
                  icon: Icons.sync_problem_rounded),
            if (s.pendingSync > 0)
              TkBanner('${s.pendingSync} transaksi menunggu sinkron',
                  body: 'Akan terkirim saat internet kembali.',
                  icon: Icons.cloud_upload_outlined),
            gap12,
            Row(children: [
              Expanded(
                  child: TkButton('Cetak struk',
                      kind: BtnKind.outline,
                      icon: Icons.print_outlined,
                      onPressed: _print)),
              const SizedBox(width: 8),
              Expanded(
                  child: TkButton('Bagikan PDF',
                      kind: BtnKind.outline,
                      icon: Icons.ios_share_rounded,
                      onPressed: () =>
                          PrinterService.I.sharePdf(t, s.businessName, s.branch))),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Kartu struk, dipakai di M16 dan M07. Memakai snapshot nama dan harga (BR-04).
class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.txn});
  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return TkCard(
      child: Column(children: [
        Text(s.businessName.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
        Text('#${txn.id} · ${tanggal(txn.time)}, ${hhmm(txn.time)}',
            style: const TextStyle(fontSize: 12, color: TK.mut)),
        const Divider(height: 24),
        for (final l in txn.lines) ...[
          InfoRow('${l.qty}× ${l.name}', rupiah(l.gross)),
          if (!l.discount.isNone)
            InfoRow('   Diskon item', rupiah(-l.priced.discountAmount), color: TK.gd),
        ],
        if (txn.totals.txnDiscount > 0)
          InfoRow('Diskon transaksi', rupiah(-txn.totals.txnDiscount)),
        if (txn.tax > 0) InfoRow('Pajak (${pctLabel(txn.taxBps)}%)', rupiah(txn.tax)),
        const Divider(height: 20),
        InfoRow('Total bayar', rupiah(txn.total), bold: true),
        if (txn.method == PayMethod.cash)
          InfoRow('Tunai / Kembalian', '${rupiah(txn.paid)} / ${rupiah(txn.change)}')
        else
          const InfoRow('Metode', 'QRIS'),
        if (txn.note.isNotEmpty) InfoRow('Catatan', txn.note),
      ]),
    );
  }
}

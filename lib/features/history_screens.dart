import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../core/printer_service.dart';
import 'payment_screens.dart';

(String, Tone) _statusBadge(Txn t) => switch (t.status) {
      TxnStatus.paid => ('Lunas', Tone.ok),
      TxnStatus.voided => ('Void', Tone.bad),
      TxnStatus.returned => ('Retur', Tone.warn),
    };

/// M06 - Riwayat transaksi
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _f = 'Shift ini';

  List<Txn> _list(AppState s) {
    final n = DateTime.now();
    switch (_f) {
      case 'Shift ini':
        return s.shiftTxns;
      case 'Kemarin':
        final y = DateTime(n.year, n.month, n.day).subtract(const Duration(days: 1));
        return s.txns
            .where((t) => DateTime(t.time.year, t.time.month, t.time.day) == y)
            .toList();
      default:
        return s.txns;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Screen(
        title: 'Riwayat transaksi',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, children: [
              for (final c in ['Shift ini', 'Kemarin', 'Semua'])
                ChoiceChip(
                  label: Text(c),
                  selected: _f == c,
                  onSelected: (_) => setState(() => _f = c),
                  showCheckmark: false,
                  selectedColor: TK.g,
                  labelStyle: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _f == c ? Colors.white : TK.ink),
                ),
            ]),
            gap16,
            TkCard(
              color: TK.g50,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Penjualan shift ini',
                    style: TextStyle(color: TK.gd, fontWeight: FontWeight.w600)),
                Price(s.salesTotal, size: 26, color: TK.gd),
                gap8,
                Row(children: [
                  Text('${s.txnCount} transaksi',
                      style: const TextStyle(color: TK.gd)),
                  const SizedBox(width: 8),
                  if (s.pendingSync > 0)
                    TkBadge('${s.pendingSync} menunggu sinkron', tone: Tone.warn),
                ]),
              ]),
            ),
            gap16,
            if (_list(s).isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(
                    child: Text('Belum ada transaksi.', style: TextStyle(color: TK.mut))),
              )
            else
              for (final t in _list(s)) ...[
                _TxnRow(t),
                gap8,
              ],
          ],
        ),
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow(this.t);
  final Txn t;
  @override
  Widget build(BuildContext context) {
    final (label, tone) = _statusBadge(t);
    return TkCard(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.pushNamed(context, Routes.detail, arguments: t.id),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('#${t.id}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${hhmm(t.time)} · ${t.method == PayMethod.cash ? 'Tunai' : 'QRIS'}',
                style: const TextStyle(fontSize: 13, color: TK.mut)),
            if (t.syncState == SyncState.pending) ...[
              const SizedBox(height: 6),
              const TkBadge('Menunggu sinkron', tone: Tone.warn),
            ] else if (t.syncState == SyncState.failed) ...[
              const SizedBox(height: 6),
              const TkBadge('Gagal sinkron', tone: Tone.bad),
            ] else if (t.needsReview) ...[
              const SizedBox(height: 6),
              const TkBadge('Stok perlu ditinjau', tone: Tone.warn),
            ],
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Price(t.total),
          const SizedBox(height: 4),
          TkBadge(label, tone: tone),
        ]),
      ]),
    );
  }
}

/// M07 - Detail transaksi
class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.txnId});
  final String txnId;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = s.txn(txnId);
        final (label, tone) = _statusBadge(t);
        final canReturn = t.status != TxnStatus.voided && t.returnableValue > 0;
        return Screen(
          title: 'Detail transaksi',
          bottom: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                  child: TkButton('Cetak struk',
                      kind: BtnKind.outline,
                      small: true,
                      icon: Icons.print_outlined,
                      onPressed: () async {
                        final ok = await PrinterService.I
                            .printReceipt(t, s.businessName, s.branch);
                        if (context.mounted && !ok) {
                          toast(context, PrinterService.I.lastError ?? 'Gagal mencetak.');
                        }
                      })),
              const SizedBox(width: 8),
              Expanded(
                  child: TkButton('Bagikan PDF',
                      kind: BtnKind.outline,
                      small: true,
                      icon: Icons.ios_share_rounded,
                      onPressed: () =>
                          PrinterService.I.sharePdf(t, s.businessName, s.branch))),
            ]),
            gap8,
            TkButton('Ajukan void atau retur',
                kind: BtnKind.danger,
                onPressed: canReturn
                    ? () => Navigator.pushNamed(context, Routes.returnReq,
                        arguments: t.id)
                    : null),
            gap8,
            const Text('Void dan retur membutuhkan persetujuan manajer',
                style: TextStyle(fontSize: 12, color: TK.mut)),
          ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('#${t.id}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  Text('${tanggal(t.time)} · ${hhmm(t.time)} WIB',
                      style: const TextStyle(color: TK.mut)),
                ]),
                TkBadge(label, tone: tone),
              ]),
              gap12,
              if (t.syncState == SyncState.pending)
                const TkBanner('Menunggu sinkron',
                    body: 'Tersimpan aman di perangkat.',
                    icon: Icons.cloud_upload_outlined)
              else if (t.syncState == SyncState.failed)
                TkBanner('Gagal sinkron',
                    body: t.syncError ?? 'Hubungi manajer.',
                    tone: Tone.bad,
                    icon: Icons.error_outline_rounded),
              if (t.needsReview)
                const TkBanner('Stok perlu ditinjau manajer',
                    body: 'Penjualan sah, tetapi stok server menjadi negatif.',
                    icon: Icons.inventory_2_outlined),
              if (t.needsReconcile)
                const TkBanner('Menunggu rekonsiliasi QRIS',
                    icon: Icons.sync_problem_rounded),
              gap12,
              ReceiptCard(txn: t),
              gap12,
              TkCard(
                child: Column(children: [
                  InfoRow('Kasir', t.cashierName.isEmpty ? s.cashierName : t.cashierName),
                  if (t.refunded > 0)
                    InfoRow('Dikembalikan', rupiah(t.refunded), color: TK.bad),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// M08 - Ajukan retur
class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key, required this.txnId});
  final String txnId;
  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  late bool _fullVoid = AppState.I.txn(widget.txnId).refunded == 0;
  late final Map<String, int> _qty = {};
  String _reason = 'Salah input';
  final _note = TextEditingController();
  static const _reasons = ['Salah input', 'Produk bermasalah', 'Pelanggan batal', 'Lainnya'];

  Txn get _t => AppState.I.txn(widget.txnId);

  int get _amount {
    if (_fullVoid) return _t.returnableValue;
    return AppState.I.refundValue(_t, {..._qty}..removeWhere((_, v) => v == 0));
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final valid = _amount > 0;
    return Screen(
      title: 'Ajukan retur',
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        TkButton('Kirim ke manajer',
            icon: Icons.send_rounded,
            onPressed: !valid
                ? null
                : () {
                    final items = _fullVoid
                        ? {for (final l in t.lines) l.productId: t.remainingQty(l)}
                        : {..._qty}..removeWhere((_, v) => v == 0);
                    Navigator.pushNamed(context, Routes.managerPin,
                        arguments: ReturnRequest(
                          txnId: t.id,
                          fullVoid: _fullVoid,
                          items: items,
                          reason: _note.text.trim().isEmpty
                              ? _reason
                              : '$_reason: ${_note.text.trim()}',
                          amount: _amount,
                        ));
                  }),
        gap8,
        const Text('Transaksi asli tidak dihapus dan tercatat di audit log',
            style: TextStyle(fontSize: 12, color: TK.mut)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: TkButton('Void semua',
                    kind: _fullVoid ? BtnKind.primary : BtnKind.outline,
                    small: true,
                    onPressed: t.refunded > 0
                        ? null
                        : () => setState(() => _fullVoid = true))),
            const SizedBox(width: 8),
            Expanded(
                child: TkButton('Retur sebagian',
                    kind: !_fullVoid ? BtnKind.primary : BtnKind.outline,
                    small: true,
                    onPressed: () => setState(() => _fullVoid = false))),
          ]),
          gap16,
          Cap('Pilih item · #${t.id}'),
          for (final l in t.lines) ...[
            TkCard(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${t.remainingQty(l)} dari ${l.qty} × ${rupiah(l.unitPrice)}',
                        style: const TextStyle(fontSize: 13, color: TK.mut)),
                  ]),
                ),
                if (_fullVoid)
                  Price(l.total)
                else
                  QtyStepper(
                    qty: _qty[l.productId] ?? 0,
                    onMinus: (_qty[l.productId] ?? 0) > 0
                        ? () => setState(() => _qty[l.productId] = (_qty[l.productId] ?? 0) - 1)
                        : null,
                    onPlus: (_qty[l.productId] ?? 0) < t.remainingQty(l)
                        ? () => setState(() => _qty[l.productId] = (_qty[l.productId] ?? 0) + 1)
                        : null,
                  ),
              ]),
            ),
            gap8,
          ],
          gap8,
          const Cap('Alasan (wajib)'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in _reasons)
              ChoiceChip(
                label: Text(r),
                selected: _reason == r,
                onSelected: (_) => setState(() => _reason = r),
                showCheckmark: false,
                selectedColor: TK.g,
                labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _reason == r ? Colors.white : TK.ink),
              ),
          ]),
          gap12,
          TkField(label: 'Catatan', controller: _note, hint: 'Opsional', maxLines: 2),
          gap16,
          TkCard(
            child: Column(children: [
              InfoRow('Dikembalikan ke pelanggan',
                  '${rupiah(_amount)}${t.method == PayMethod.cash ? ' tunai' : ''}',
                  bold: true),
              InfoRow(
                  'Stok bertambah',
                  _fullVoid
                      ? '${t.lines.fold(0, (a, l) => a + t.remainingQty(l))} item'
                      : '${_qty.values.fold(0, (a, b) => a + b)} item'),
            ]),
          ),
        ],
      ),
    );
  }
}

/// M09 - Persetujuan manajer (PIN)
class ManagerPinScreen extends StatefulWidget {
  const ManagerPinScreen({super.key, required this.request});
  final ReturnRequest request;
  @override
  State<ManagerPinScreen> createState() => _ManagerPinScreenState();
}

class _ManagerPinScreenState extends State<ManagerPinScreen> {
  String _pin = '';
  bool _wrong = false;

  void _tap(String d) {
    if (_pin.length >= 4 || AppState.I.pinLockRemaining != null) return;
    setState(() {
      _pin += d;
      _wrong = false;
    });
    if (_pin.length == 4) _verify();
  }

  Future<void> _verify() async {
    final s = AppState.I;
    // PIN diverifikasi lokal (hash + salt) sehingga void/retur bisa offline.
    final approver = s.verifyManagerPin(_pin);
    if (approver == null) {
      setState(() {
        _wrong = true;
        _pin = '';
      });
      return;
    }
    try {
      await s.applyReturn(widget.request, approver);
      if (!mounted) return;
      Navigator.popUntil(context, (r) => r.settings.name == Routes.history);
      toast(context,
          'Disetujui ${approver.name}. ${widget.request.fullVoid ? 'Transaksi di-void' : 'Retur diproses'}.');
    } on BusinessRuleException catch (e) {
      if (!mounted) return;
      setState(() => _pin = '');
      toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Screen(
      title: 'Persetujuan manajer',
      bottom: TkButton('Batalkan pengajuan',
          kind: BtnKind.outline, onPressed: () => Navigator.pop(context)),
      child: Column(
        children: [
          const Text('Minta manajer memasukkan PIN',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          gap8,
          const Text('Retur tidak bisa diproses tanpa persetujuan.',
              style: TextStyle(color: TK.mut)),
          gap16,
          TkCard(
            child: Column(children: [
              InfoRow('Pengajuan', r.fullVoid ? 'Void semua' : 'Retur sebagian'),
              InfoRow('Transaksi', '#${r.txnId}'),
              InfoRow('Nilai', rupiah(r.amount)),
              InfoRow('Diajukan oleh', '${AppState.I.cashierName.split(' ').first} (kasir)'),
            ]),
          ),
          gap24,
          const Text('PIN manajer (4 digit)',
              style: TextStyle(fontSize: 13, color: TK.mut)),
          gap12,
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? TK.g : Colors.transparent,
                  border: Border.all(color: _wrong ? TK.bad : TK.g, width: 2),
                ),
              ),
          ]),
          if (_wrong)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  AppState.I.pinLockRemaining != null
                      ? 'Terlalu banyak percobaan. Coba lagi ${AppState.I.pinLockRemaining!.inSeconds} detik lagi.'
                      : 'PIN salah. Coba lagi.${AppState.demoMode ? ' (demo: 1234)' : ''}',
                  style: const TextStyle(color: TK.bad, fontSize: 12)),
            ),
          gap24,
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', '⌫'],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                for (final k in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: k.isEmpty
                          ? const SizedBox(height: 52)
                          : SizedBox(
                              height: 52,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: TK.ink,
                                    side: const BorderSide(color: TK.line),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14))),
                                onPressed: () => k == '⌫'
                                    ? setState(() => _pin = _pin.isEmpty
                                        ? ''
                                        : _pin.substring(0, _pin.length - 1))
                                    : _tap(k),
                                child: Text(k,
                                    style: const TextStyle(
                                        fontSize: 20, fontWeight: FontWeight.w600)),
                              ),
                            ),
                    ),
                  ),
              ]),
            ),
        ],
      ),
    );
  }
}

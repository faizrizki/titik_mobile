import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/printer_service.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import 'payment_screens.dart';

(String, Tone, IconData?) _statusBadge(Txn t) => switch (t.status) {
      TxnStatus.paid => ('Lunas', Tone.ok, Icons.check_rounded),
      TxnStatus.voided => ('Void', Tone.bad, null),
      TxnStatus.returned => ('Retur', Tone.warn, null),
    };

/// M06 - Riwayat transaksi
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _f = 'Shift ini';
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Txn> _list(AppState s) {
    final n = DateTime.now();
    var l = switch (_f) {
      'Shift ini' => s.shiftTxns,
      'Kemarin' => () {
          final y = DateTime(n.year, n.month, n.day).subtract(const Duration(days: 1));
          return s.txns
              .where((t) => DateTime(t.time.year, t.time.month, t.time.day) == y)
              .toList();
        }(),
      _ => s.txns,
    };
    final q = _q.text.trim().toLowerCase();
    if (q.isNotEmpty) l = l.where((t) => t.id.toLowerCase().contains(q)).toList();
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final list = _list(s);
        return Screen(
          title: 'Riwayat transaksi',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TkSegmented<String>(
                options: const [
                  ('Shift ini', 'Shift ini'),
                  ('Kemarin', 'Kemarin'),
                  ('Semua', 'Semua')
                ],
                value: _f,
                onChanged: (v) => setState(() => _f = v),
              ),
              gap16,
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: TK.g50, borderRadius: BorderRadius.circular(20)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Penjualan shift ini',
                          style: TextStyle(color: TK.gd, fontWeight: FontWeight.w600)),
                      Price(s.salesTotal, size: 34, color: TK.gd),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${s.txnCount} transaksi',
                        style: const TextStyle(
                            color: TK.gd, fontWeight: FontWeight.w700, fontSize: 15)),
                    if (s.pendingSync > 0)
                      Text('${s.pendingSync} menunggu sinkron',
                          style: const TextStyle(color: TK.mut, fontSize: 13)),
                  ]),
                ]),
              ),
              gap16,
              TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Cari nomor transaksi',
                  hintStyle: const TextStyle(color: TK.mut),
                  prefixIcon: const Icon(Icons.search_rounded, color: TK.mut),
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
              gap8,
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(
                      child: Text('Belum ada transaksi.', style: TextStyle(color: TK.mut))),
                )
              else
                for (var i = 0; i < list.length; i++) ...[
                  _TxnRow(list[i]),
                  if (i < list.length - 1) const Divider(height: 1),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow(this.t);
  final Txn t;
  @override
  Widget build(BuildContext context) {
    final (label, tone, _) = _statusBadge(t);
    return InkWell(
      onTap: () => Navigator.pushNamed(context, Routes.detail, arguments: t.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          IconTile(
              t.method == PayMethod.cash
                  ? Icons.receipt_long_outlined
                  : Icons.qr_code_2_rounded,
              size: 48,
              bg: TK.neutralBg,
              fg: TK.mut),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('#${t.id}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 2),
              Text('${hhmm(t.time)} · ${t.method == PayMethod.cash ? 'Tunai' : 'QRIS'}',
                  style: const TextStyle(fontSize: 14, color: TK.mut)),
              if (t.syncState == SyncState.pending) ...[
                const SizedBox(height: 4),
                const Row(children: [
                  Icon(Icons.schedule_rounded, size: 15, color: TK.warn),
                  SizedBox(width: 4),
                  Text('Menunggu sinkron',
                      style: TextStyle(
                          fontSize: 13, color: TK.warn, fontWeight: FontWeight.w600)),
                ]),
              ] else if (t.syncState == SyncState.failed) ...[
                const SizedBox(height: 4),
                const Row(children: [
                  Icon(Icons.error_outline_rounded, size: 15, color: TK.bad),
                  SizedBox(width: 4),
                  Text('Gagal sinkron',
                      style: TextStyle(
                          fontSize: 13, color: TK.bad, fontWeight: FontWeight.w600)),
                ]),
              ] else if (t.needsReview) ...[
                const SizedBox(height: 4),
                const Text('Stok perlu ditinjau',
                    style: TextStyle(
                        fontSize: 13, color: TK.warn, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Price(t.total, size: 16),
            const SizedBox(height: 6),
            TkBadge(label, tone: tone),
          ]),
        ]),
      ),
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
        final (label, tone, icon) = _statusBadge(t);
        final canReturn = t.status != TxnStatus.voided && t.returnableValue > 0;
        final shift = s.shifts.where((x) => x.uuid == t.shiftId);
        final shiftText = shift.isEmpty
            ? null
            : '${hhmm(shift.first.openedAt)}–${shift.first.closedAt == null ? 'sekarang' : hhmm(shift.first.closedAt!)} WIB';
        return Screen(
          title: 'Detail transaksi',
          bottom: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                  child: TkButton('Cetak struk',
                      kind: BtnKind.soft,
                      icon: Icons.print_outlined,
                      onPressed: () async {
                        final ok = await PrinterService.I
                            .printReceipt(t, s.businessName, s.branch);
                        if (context.mounted && !ok) {
                          toast(context, PrinterService.I.lastError ?? 'Gagal mencetak.');
                        }
                      })),
              const SizedBox(width: 10),
              Expanded(
                  child: TkButton('Bagikan',
                      kind: BtnKind.soft,
                      icon: Icons.ios_share_rounded,
                      onPressed: () =>
                          PrinterService.I.sharePdf(t, s.businessName, s.branch))),
            ]),
            gap8,
            TkButton('Ajukan void atau retur',
                kind: BtnKind.danger,
                icon: Icons.undo_rounded,
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
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                  Text('${tanggal(t.time)} · ${hhmm(t.time)} WIB',
                      style: const TextStyle(color: TK.mut)),
                ]),
                TkBadge(label, tone: tone, icon: icon),
              ]),
              gap16,
              if (t.syncState == SyncState.pending) ...[
                const TkBanner('Menunggu sinkron',
                    body: 'Tersimpan aman di perangkat.',
                    icon: Icons.schedule_rounded),
                gap12,
              ] else if (t.syncState == SyncState.failed) ...[
                TkBanner('Gagal sinkron',
                    body: t.syncError ?? 'Hubungi manajer.',
                    tone: Tone.bad,
                    icon: Icons.error_outline_rounded),
                gap12,
              ],
              if (t.needsReview) ...[
                const TkBanner('Stok perlu ditinjau manajer',
                    body: 'Penjualan sah, tetapi stok server menjadi negatif.',
                    icon: Icons.inventory_2_outlined),
                gap12,
              ],
              if (t.needsReconcile) ...[
                const TkBanner('Menunggu rekonsiliasi QRIS',
                    icon: Icons.sync_problem_rounded),
                gap12,
              ],
              ReceiptCard(txn: t, detail: true),
              gap12,
              TkCard(
                child: Column(children: [
                  if (shiftText != null) InfoRow('Shift', shiftText),
                  if (t.refunded > 0)
                    InfoRow('Dikembalikan', rupiah(t.refunded), color: TK.bad),
                  if (shiftText == null && t.refunded == 0)
                    InfoRow('Kasir', t.cashierName.isEmpty ? s.cashierName : t.cashierName),
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
  final Map<String, int> _qty = {};
  String _reason = 'Salah input';
  final _note = TextEditingController();
  static const _reasons = ['Salah input', 'Produk bermasalah', 'Pelanggan batal', 'Lainnya'];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Txn get _t => AppState.I.txn(widget.txnId);

  Map<String, int> get _items => _fullVoid
      ? {for (final l in _t.lines) l.productId: _t.remainingQty(l)}
      : ({..._qty}..removeWhere((_, v) => v <= 0));

  int get _amount =>
      _fullVoid ? _t.returnableValue : AppState.I.refundValue(_t, _items);

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final valid = _amount > 0;
    final items = _items;
    final stockText = items.length == 1
        ? () {
            final l = t.lines.firstWhere((l) => l.productId == items.keys.first);
            return '${l.name} +${items.values.first}';
          }()
        : '${items.values.fold(0, (a, b) => a + b)} item';
    return Screen(
      title: 'Ajukan retur',
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        TkButton('Kirim ke manajer',
            trailing: Icons.arrow_forward_rounded,
            onPressed: !valid
                ? null
                : () => Navigator.pushNamed(context, Routes.managerPin,
                    arguments: ReturnRequest(
                      txnId: t.id,
                      fullVoid: _fullVoid,
                      items: items,
                      reason: _note.text.trim().isEmpty
                          ? _reason
                          : '$_reason: ${_note.text.trim()}',
                      amount: _amount,
                    ))),
        gap8,
        const Text('Transaksi asli tidak dihapus dan tercatat di audit log',
            style: TextStyle(fontSize: 12, color: TK.mut)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(
            ignoring: t.refunded > 0,
            child: Opacity(
              opacity: t.refunded > 0 ? .6 : 1,
              child: TkSegmented<bool>(
                options: const [(true, 'Void semua'), (false, 'Retur sebagian')],
                value: _fullVoid,
                onChanged: (v) => setState(() => _fullVoid = v),
              ),
            ),
          ),
          gap16,
          Text('Pilih item · #${t.id}',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: TK.mut)),
          gap8,
          TkCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              for (var i = 0; i < t.lines.length; i++) ...[
                _returnRow(t, t.lines[i]),
                if (i < t.lines.length - 1) const Divider(height: 1),
              ],
            ]),
          ),
          gap24,
          const Text('Alasan (wajib)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TK.mut)),
          gap8,
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in _reasons)
              ChoiceChip(
                label: Text(r),
                selected: _reason == r,
                onSelected: (_) => setState(() => _reason = r),
                showCheckmark: false,
                selectedColor: TK.g,
                backgroundColor: Colors.white,
                side: BorderSide(color: _reason == r ? TK.g : TK.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
              InfoRow('Stok bertambah', items.isEmpty ? '—' : stockText),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _returnRow(Txn t, TxnLine l) {
    final remaining = t.remainingQty(l);
    final selected = _fullVoid ? remaining > 0 : (_qty[l.productId] ?? 0) > 0;
    final q = _qty[l.productId] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Semantics(
          checked: selected,
          label: 'Pilih ${l.name}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _fullVoid || remaining == 0
                ? null
                : () => setState(
                    () => selected ? _qty.remove(l.productId) : _qty[l.productId] = 1),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? TK.g : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected ? TK.g : TK.line, width: 1.6),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text('$remaining dari ${l.qty} × ${rupiah(l.unitPrice)}',
                style: const TextStyle(fontSize: 13, color: TK.mut)),
          ]),
        ),
        if (!_fullVoid && selected)
          QtyStepper(
            qty: q,
            onMinus: q > 1 ? () => setState(() => _qty[l.productId] = q - 1) : null,
            onPlus: q < remaining ? () => setState(() => _qty[l.productId] = q + 1) : null,
          )
        else
          Price(l.total, size: 15),
      ]),
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
  bool _busy = false;

  void _tap(String d) {
    if (_pin.length >= 4 || AppState.I.pinLockRemaining != null) return;
    setState(() {
      _pin += d;
      _wrong = false;
    });
  }

  Future<void> _verify() async {
    if (_pin.length < 4 || _busy) return;
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
    setState(() => _busy = true);
    try {
      await s.applyReturn(widget.request, approver);
      if (!mounted) return;
      Navigator.popUntil(context, (r) => r.settings.name == Routes.history);
      toast(context,
          'Disetujui ${approver.name}. ${widget.request.fullVoid ? 'Transaksi di-void' : 'Retur diproses'}.');
    } on BusinessRuleException catch (e) {
      if (!mounted) return;
      setState(() {
        _pin = '';
        _busy = false;
      });
      toast(context, e.message);
    }
  }

  Widget _key(Widget child, VoidCallback? onTap, {bool primary = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: SizedBox(
            height: 64,
            child: Material(
              color: primary ? TK.g : Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onTap,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: primary ? TK.g : TK.line),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final s = AppState.I;
    final approvers = s.session?.approvers ?? const <Approver>[];
    final who =
        approvers.length == 1 ? 'PIN ${approvers.first.name} · Manajer' : 'PIN manajer';
    final lock = s.pinLockRemaining;
    Widget num(String d) => _key(
        Text(d, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        () => _tap(d));
    return Screen(
      title: 'Persetujuan manajer',
      bottom: TkButton('Batalkan pengajuan',
          kind: BtnKind.outline, onPressed: () => Navigator.pop(context)),
      child: Column(
        children: [
          const IconTile(Icons.lock_outline_rounded, size: 76),
          gap16,
          const Text('Minta manajer memasukkan PIN',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          gap8,
          const Text('Retur tidak bisa diproses tanpa persetujuan.',
              style: TextStyle(color: TK.mut)),
          gap16,
          TkCard(
            child: Column(children: [
              InfoRow('Pengajuan', r.fullVoid ? 'Void semua' : 'Retur sebagian'),
              InfoRow('Transaksi', '#${r.txnId}'),
              InfoRow('Nilai', rupiah(r.amount)),
              InfoRow('Diajukan oleh', '${s.cashierName.split(' ').first} (kasir)'),
            ]),
          ),
          gap16,
          Text(who, style: const TextStyle(fontSize: 14, color: TK.mut)),
          gap12,
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 9),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? TK.g : Colors.transparent,
                  border: Border.all(color: _wrong ? TK.bad : TK.g, width: 2),
                ),
              ),
          ]),
          if (_wrong || lock != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  lock != null
                      ? 'Terlalu banyak percobaan. Coba lagi ${lock.inSeconds} detik lagi.'
                      : 'PIN salah. Coba lagi.${AppState.demoMode ? ' (demo: 1234)' : ''}',
                  style: const TextStyle(color: TK.bad, fontSize: 13)),
            ),
          gap16,
          Row(children: [num('1'), num('2'), num('3')]),
          Row(children: [num('4'), num('5'), num('6')]),
          Row(children: [num('7'), num('8'), num('9')]),
          Row(children: [
            _key(const Icon(Icons.backspace_outlined, size: 22), () {
              if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
            }),
            num('0'),
            _key(const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                _pin.length == 4 && !_busy ? _verify : null,
                primary: true),
          ]),
        ],
      ),
    );
  }
}

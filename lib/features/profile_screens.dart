import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/printer_service.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/app_state.dart';
import '../data/models.dart';

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.title, {this.value, this.onTap});
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        minTileHeight: 48,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: TK.g50, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: TK.gd),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (value != null)
            Text(value!, style: const TextStyle(color: TK.mut, fontSize: 13)),
          const Icon(Icons.chevron_right_rounded, color: TK.mut),
        ]),
      );
}

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}

String _roleLabel(String r) =>
    switch (r) { 'owner' => 'Owner', 'manager' => 'Manajer', _ => 'Kasir' };

/// M11 - Profil & pengaturan
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return ListenableBuilder(
      listenable: Listenable.merge([s, PrinterService.I]),
      builder: (context, _) => Screen(
        title: 'Profil & pengaturan',
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TkCard(
              child: Row(children: [
                CircleAvatar(
                    radius: 26,
                    backgroundColor: TK.g50,
                    child: Text(_initials(s.cashierName),
                        style: const TextStyle(color: TK.gd, fontWeight: FontWeight.w800))),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.cashierName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text('${_roleLabel(s.role)} · ${s.branch}',
                        style: const TextStyle(color: TK.mut, fontSize: 13)),
                  ]),
                ),
                if (s.shiftOpen) const TkBadge('Shift aktif'),
              ]),
            ),
            gap16,
            const Cap('Perangkat'),
            TkCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _MenuRow(Icons.print_outlined, 'Printer struk',
                    value: PrinterService.I.device?.name ?? 'Belum dipilih',
                    onTap: () => Navigator.pushNamed(context, Routes.printer)),
                const Divider(),
                _MenuRow(Icons.sync_rounded, 'Sinkronisasi',
                    value: s.failedSync > 0
                        ? '${s.failedSync} perlu bantuan'
                        : '${s.pendingSync} menunggu',
                    onTap: () => Navigator.pushNamed(context, Routes.sync)),
                const Divider(),
                _MenuRow(Icons.receipt_long_rounded, 'Riwayat transaksi',
                    value: '${s.shiftTxns.length} shift ini',
                    onTap: () => Navigator.pushNamed(context, Routes.history)),
              ]),
            ),
            gap16,
            const Cap('Shift'),
            TkCard(
              padding: EdgeInsets.zero,
              child: _MenuRow(Icons.lock_clock_outlined, 'Tutup shift',
                  value: s.shiftOpen ? 'Sejak ${hhmm(s.shiftStart)}' : 'Tidak ada shift',
                  onTap: s.shiftOpen
                      ? () => Navigator.pushNamed(context, Routes.closeShift)
                      : null),
            ),
            gap16,
            const Cap('Akun'),
            TkCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _MenuRow(Icons.password_rounded, 'Ganti kata sandi',
                    onTap: () => toast(context,
                        'Kata sandi diubah oleh pemilik di dashboard web.')),
                const Divider(),
                _MenuRow(Icons.help_outline_rounded, 'Bantuan',
                    onTap: () => toast(context, 'Hubungi manajer atau pemilik usaha.')),
              ]),
            ),
            gap16,
            TkButton('Keluar dari akun', kind: BtnKind.danger, onPressed: () async {
              try {
                await s.logout();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, Routes.login, (r) => false);
                }
              } on BusinessRuleException catch (e) {
                if (context.mounted) toast(context, e.message);
              }
            }),
            gap12,
            Center(
              child: Text(
                  'titik versi 1.0.0${AppState.demoMode ? ' · mode demo' : ''} · Data yang belum tersinkron tetap aman',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: TK.mut)),
            ),
          ],
        ),
      ),
    );
  }
}

/// M12 - Printer struk (Bluetooth, kertas 58 mm / 80 mm)
class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});
  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  List<PrinterDevice> _devices = const [];
  bool _scanning = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _msg = null;
    });
    try {
      final t = PrinterService.I.transport;
      if (!await t.bluetoothOn()) {
        _msg = 'Bluetooth mati atau izin belum diberikan.';
        _devices = const [];
      } else {
        _devices = await t.paired();
        if (_devices.isEmpty) {
          _msg = 'Belum ada printer yang dipasangkan. Pasangkan lewat pengaturan Bluetooth HP.';
        }
      }
    } catch (e) {
      _msg = 'Gagal mencari printer: $e';
    }
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = PrinterService.I;
    final s = AppState.I;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) => Screen(
        title: 'Printer struk',
        bottom: Column(mainAxisSize: MainAxisSize.min, children: [
          TkButton('Cetak halaman uji',
              icon: Icons.print_rounded,
              onPressed: () async {
                final ok = await p.printTestPage(s.businessName, s.branch);
                if (context.mounted) {
                  toast(context,
                      ok ? 'Halaman uji dikirim.' : (p.lastError ?? 'Gagal mencetak.'));
                }
              }),
          gap8,
          const Text('Struk tetap bisa dicetak tanpa internet',
              style: TextStyle(fontSize: 12, color: TK.mut)),
        ]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: p.device != null ? TK.g50 : TK.warnBg,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                IconTile(
                    p.device != null
                        ? Icons.bluetooth_connected_rounded
                        : Icons.bluetooth_disabled_rounded,
                    size: 52,
                    bg: Colors.white,
                    fg: p.device != null ? TK.gd : TK.warn),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.device != null ? '${p.device!.name} dipilih' : 'Belum ada printer dipilih',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: p.device != null ? TK.gd : TK.warn)),
                    Text(
                        p.device != null
                            ? 'Bluetooth · kertas ${p.paperMm} mm'
                            : 'Pilih printer di bawah, atau bagikan struk sebagai PDF.',
                        style: TextStyle(
                            fontSize: 13, color: p.device != null ? TK.gd : TK.warn)),
                  ]),
                ),
              ]),
            ),
            gap24,
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Printer terpasang',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TK.mut)),
              TextButton(
                  onPressed: _scanning ? null : _scan,
                  child: Text(_scanning ? 'Mencari…' : 'Cari ulang',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            if (_msg != null) ...[
              Text(_msg!, style: const TextStyle(fontSize: 13, color: TK.mut)),
              gap8,
            ],
            if (_devices.isNotEmpty)
              TkCard(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(children: [
                  for (var i = 0; i < _devices.length; i++) ...[
                    _deviceRow(context, p, _devices[i]),
                    if (i < _devices.length - 1) const Divider(height: 1),
                  ],
                ]),
              ),
            gap24,
            const Text('Ukuran kertas',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TK.mut)),
            gap8,
            TkSegmented<int>(
              options: const [(58, '58 mm'), (80, '80 mm')],
              value: p.paperMm,
              onChanged: (v) {
                p.paperMm = v;
                p.save();
              },
            ),
            gap16,
            TkCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SwitchListTile(
                    value: p.autoPrint,
                    activeColor: Colors.white,
                    activeTrackColor: TK.g,
                    title: const Text('Cetak otomatis setelah bayar',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Struk langsung keluar'),
                    onChanged: (v) {
                      p.autoPrint = v;
                      p.save();
                    }),
                const Divider(),
                SwitchListTile(
                    value: p.showCashier,
                    activeColor: Colors.white,
                    activeTrackColor: TK.g,
                    title: const Text('Tampilkan nama kasir',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    onChanged: (v) {
                      p.showCashier = v;
                      p.save();
                    }),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceRow(BuildContext context, PrinterService p, PrinterDevice d) {
    final selected = p.device?.address == d.address;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        IconTile(Icons.print_outlined,
            size: 46,
            bg: selected ? TK.g50 : TK.neutralBg,
            fg: selected ? TK.gd : TK.mut),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(d.address, style: const TextStyle(fontSize: 12, color: TK.mut)),
          ]),
        ),
        if (selected)
          const TkBadge('Terhubung', icon: Icons.check_rounded)
        else
          SizedBox(
            width: 112,
            child: TkButton('Hubungkan',
                kind: BtnKind.soft,
                small: true,
                onPressed: () async {
                  final ok = await p.connectTo(d);
                  if (context.mounted && !ok) {
                    toast(context, p.lastError ?? 'Gagal terhubung.');
                  }
                }),
          ),
      ]),
    );
  }
}

String _outboxLabel(OutboxItem o) => switch (o.type) {
      'order' => 'Transaksi',
      'refund' => 'Void / retur',
      'shift' => 'Shift',
      _ => o.type,
    };

/// M17 - Sinkronisasi dan layar "Masalah sinkronisasi"
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final sync = s.sync;
        final failed = s.failedOutbox;
        final pending = s.pendingOutbox;
        final last = s.lastSyncAt;

        Future<void> retry() async {
          if (sync == null) return;
          await sync.syncNow(force: true);
          if (!context.mounted) return;
          toast(
              context,
              s.outbox.isEmpty
                  ? 'Semua data tersinkron.'
                  : (sync.lastError ?? 'Masih ada data yang belum terkirim.'));
        }

        return Screen(
          title: 'Sinkronisasi',
          bottom: Column(mainAxisSize: MainAxisSize.min, children: [
            if (failed.isNotEmpty)
              TkButton('Hubungi manajer',
                  onPressed: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Hubungi manajer'),
                          content: const Text(
                              'Minta manajer memeriksa akses cabang Anda, lalu tekan "Ulangi sinkronisasi". Transaksi tetap tersimpan di perangkat.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Mengerti'))
                          ],
                        ),
                      ))
            else
              TkButton(sync?.syncing == true ? 'Menyinkronkan…' : 'Ulangi sinkronisasi',
                  icon: Icons.sync_rounded,
                  onPressed: sync == null || sync.syncing ? null : retry),
            gap8,
            const Text('Jangan hapus data aplikasi saat ada antrean.',
                style: TextStyle(fontSize: 12, color: TK.mut)),
          ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: s.online ? TK.g50 : TK.warnBg,
                    borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Icon(s.online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: s.online ? TK.gd : TK.warn),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.online ? 'Online' : 'Offline',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: s.online ? TK.gd : TK.warn)),
                      Text(
                          last == null
                              ? 'Belum pernah sinkron'
                              : 'Sinkron terakhir ${hhmm(last)} WIB',
                          style: TextStyle(
                              fontSize: 13, color: s.online ? TK.gd : TK.warn)),
                    ]),
                  ),
                ]),
              ),
              gap16,
              const Text('Data aman, usaha jalan.',
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.6)),
              const Text('Transaksi dikirim otomatis tanpa duplikat.',
                  style: TextStyle(color: TK.mut)),
              gap12,
              if (AppState.demoMode) ...[
                const TkBanner('Mode demo',
                    body: 'Terhubung ke server simulasi di dalam aplikasi.',
                    icon: Icons.science_outlined),
                gap12,
              ],
              if (sync?.authExpired == true) ...[
                const TkBanner('Sesi berakhir',
                    body: 'Masuk kembali agar antrean bisa terkirim. Data tetap aman di perangkat.',
                    tone: Tone.bad,
                    icon: Icons.lock_outline_rounded),
                gap12,
              ] else if (sync?.lastError != null && pending.isNotEmpty) ...[
                TkBanner('Menunggu koneksi',
                    body: '${sync!.lastError}. Dicoba lagi otomatis dengan jeda bertahap.',
                    icon: Icons.schedule_rounded),
                gap12,
              ],
              Row(children: [
                _Stat('${s.syncedCount}', 'Tersinkron', TK.gd, TK.g50),
                const SizedBox(width: 10),
                _Stat('${pending.length}', 'Menunggu', TK.ink, Colors.white, border: true),
                const SizedBox(width: 10),
                _Stat('${failed.length}', 'Perlu bantuan', TK.bad, TK.badBg),
              ]),
              gap24,
              if (failed.isNotEmpty) ...[
                const Text('Perlu ditinjau',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                gap8,
                for (final o in failed) ...[
                  TkCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.warning_amber_rounded, color: TK.bad, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                o.type == 'order'
                                    ? '#${s.txnByUuid(o.id)?.id ?? o.id.substring(0, 8)}'
                                    : _outboxLabel(o),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 17))),
                        if (o.type == 'order' && s.txnByUuid(o.id) != null)
                          Price(s.txnByUuid(o.id)!.total),
                      ]),
                      const SizedBox(height: 8),
                      Text(o.error ?? 'Ditolak server',
                          style: const TextStyle(
                              color: TK.bad, fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      const Text(
                          'Transaksi tetap tersimpan di perangkat. Minta manajer memeriksa akses Anda, lalu coba sinkronkan kembali.',
                          style: TextStyle(fontSize: 13, color: TK.mut)),
                      gap12,
                      TkButton('Ulangi sinkronisasi',
                          kind: BtnKind.soft,
                          icon: Icons.history_rounded,
                          onPressed: sync == null || sync.syncing ? null : retry),
                    ]),
                  ),
                  gap8,
                ],
                gap8,
              ],
              if (pending.isNotEmpty) ...[
                const Text('Menunggu dikirim',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                gap8,
                for (final o in pending) ...[
                  TkCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Icon(Icons.schedule_rounded, color: TK.warn, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              '${_outboxLabel(o)}${o.type == 'order' ? ' #${s.txnByUuid(o.id)?.id ?? ''}' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w700))),
                      if (o.attempts > 0)
                        Text('${o.attempts}× dicoba',
                            style: const TextStyle(fontSize: 12, color: TK.mut)),
                      if (o.type == 'order' && s.txnByUuid(o.id) != null) ...[
                        const SizedBox(width: 8),
                        Price(s.txnByUuid(o.id)!.total),
                      ],
                    ]),
                  ),
                  gap8,
                ],
              ],
              if (failed.isEmpty && pending.isEmpty)
                TkCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const IconTile(Icons.check_rounded, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Semua sudah tersinkron',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(last == null ? '' : 'Berhasil disinkronkan · ${hhmm(last)}',
                            style: const TextStyle(fontSize: 13, color: TK.mut)),
                      ]),
                    ),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.n, this.label, this.color, this.bg, {this.border = false});
  final String n;
  final String label;
  final Color color;
  final Color bg;
  final bool border;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: border ? Border.all(color: TK.line) : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: TextStyle(fontSize: 13, color: color == TK.ink ? TK.mut : color)),
          ]),
        ),
      );
}

/// M18 - Tutup shift
class CloseShiftScreen extends StatefulWidget {
  const CloseShiftScreen({super.key});
  @override
  State<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends State<CloseShiftScreen> {
  final _phys = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phys.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _close(int phys) async {
    setState(() => _busy = true);
    try {
      await AppState.I.closeShift(phys, note: _note.text);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, Routes.shiftDone, (r) => false);
    } on BusinessRuleException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final sm = s.summary;
    if (sm == null || !s.shiftOpen) {
      return const Screen(
          title: 'Tutup shift',
          child: Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: Text('Tidak ada shift terbuka.'))));
    }
    final expected = sm.expectedCash;
    final phys = parseRupiah(_phys.text);
    final diff = phys - expected;
    return Screen(
      title: 'Tutup shift',
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        TkButton('Simpan & tutup shift',
            trailing: Icons.arrow_forward_rounded,
            onPressed: _phys.text.isEmpty || _busy ? null : () => _close(phys)),
        gap8,
        Text(
            s.pendingSync == 0
                ? 'Seluruh transaksi shift sudah tersinkron.'
                : '${s.pendingSync} transaksi belum tersinkron, akan dikirim otomatis.',
            style: TextStyle(
                fontSize: 12, color: s.pendingSync == 0 ? TK.gd : TK.mut)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration:
                BoxDecoration(color: TK.g50, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const IconTile(Icons.schedule_rounded, size: 44, bg: Colors.white, fg: TK.gd),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Shift · ${s.branch}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16, color: TK.gd)),
                  Text('${tanggal(s.shiftStart)} · ${hhmm(s.shiftStart)}–sekarang WIB',
                      style: const TextStyle(fontSize: 13, color: TK.gd)),
                ]),
              ),
            ]),
          ),
          gap24,
          const Text('Cocokkan kas hari ini',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.6)),
          const Text('Hitung uang tunai di laci sebelum menutup.',
              style: TextStyle(color: TK.mut)),
          gap16,
          TkCard(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              InfoRow('Kas awal', rupiah(s.openingCash)),
              InfoRow('Penjualan tunai', rupiah(sm.cashSales)),
              InfoRow('Retur tunai', sm.cashRefunds > 0 ? rupiah(-sm.cashRefunds) : 'Rp0'),
              const Divider(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Kas seharusnya',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Price(expected, size: 18),
              ]),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('QRIS ${rupiah(sm.qrisSales)} tidak masuk perhitungan kas.',
                    style: const TextStyle(fontSize: 12, color: TK.mut)),
              ),
            ]),
          ),
          gap16,
          TkField(
            label: 'Kas akhir fisik',
            controller: _phys,
            prefix: 'Rp ',
            digitsOnly: true,
            keyboard: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          gap12,
          if (_phys.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                  color: diff == 0 ? TK.g50 : (diff < 0 ? TK.badBg : TK.warnBg),
                  borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(
                    diff == 0
                        ? 'Kas cocok'
                        : 'Selisih kas ${diff < 0 ? 'kurang' : 'lebih'}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: diff == 0 ? TK.gd : (diff < 0 ? TK.bad : TK.warn))),
                Text(rupiah(diff),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: diff == 0 ? TK.gd : (diff < 0 ? TK.bad : TK.warn))),
              ]),
            ),
          gap16,
          TkField(
              label: 'Catatan selisih',
              controller: _note,
              hint: 'Opsional',
              maxLines: 2),
        ],
      ),
    );
  }
}

/// M10 - Shift selesai
class ShiftDoneScreen extends StatelessWidget {
  const ShiftDoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final sh = s.activeShift;
    if (sh == null || sh.isOpen) {
      return const Screen(
          title: 'Shift selesai',
          showBack: false,
          child: Center(child: Text('Tidak ada shift yang selesai.')));
    }
    final diff = sh.difference ?? 0;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ListenableBuilder(
            listenable: s,
            builder: (context, _) => Column(
              children: [
                gap16,
                Container(
                  width: 104,
                  height: 104,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: TK.g50),
                  child: const Icon(Icons.check_rounded, color: TK.gd, size: 52),
                ),
                gap16,
                const Text('Shift selesai',
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                const SizedBox(height: 4),
                Text(
                    'Terima kasih, ${s.cashierName.split(' ').first}. ${s.pendingSync == 0 ? 'Semua transaksi sudah tersinkron.' : 'Transaksi akan tersinkron otomatis.'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: TK.mut)),
                gap24,
                TkCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    InfoRow('Waktu shift', '${hhmm(sh.openedAt)}–${hhmm(sh.closedAt!)} WIB'),
                    InfoRow('Transaksi', '${sh.txnCount}'),
                    InfoRow('Penjualan tunai', rupiah(sh.cashSales)),
                    InfoRow('Penjualan QRIS', rupiah(sh.qrisSales)),
                    const Divider(height: 24),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Total penjualan',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      Price(sh.salesTotal, size: 20),
                    ]),
                  ]),
                ),
                gap12,
                TkCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    InfoRow('Kas seharusnya', rupiah(sh.expectedCash ?? 0)),
                    InfoRow('Kas fisik', rupiah(sh.closingCash ?? 0)),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Selisih kas',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: diff == 0 ? TK.g50 : TK.badBg,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(rupiah(diff),
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: diff == 0 ? TK.gd : TK.bad)),
                        ),
                      ]),
                    ),
                  ]),
                ),
                if (diff != 0) ...[
                  gap12,
                  const TkBanner('Selisih dikirim ke manajer',
                      body: 'Manajer akan meninjau bersama Anda.',
                      icon: Icons.warning_amber_rounded),
                ],
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
            TkButton('Cetak laporan shift',
                kind: BtnKind.soft,
                icon: Icons.print_outlined,
                onPressed: () async {
                  final ok = await PrinterService.I
                      .printShiftReport(sh, s.businessName, s.branch);
                  if (context.mounted) {
                    toast(context,
                        ok ? 'Laporan dikirim ke printer.' : (PrinterService.I.lastError ?? 'Gagal mencetak.'));
                  }
                }),
            gap8,
            TkButton('Keluar dari akun', onPressed: () async {
              try {
                await s.logout();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, Routes.login, (r) => false);
                }
              } on BusinessRuleException catch (e) {
                if (context.mounted) toast(context, e.message);
              }
            }),
            TextButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, Routes.openShift, (r) => false),
                child: const Text('Mulai shift baru',
                    style: TextStyle(fontWeight: FontWeight.w700))),
            const Text('Keluar akun tersedia setelah semua data terkirim',
                style: TextStyle(fontSize: 12, color: TK.mut)),
          ]),
        ),
      ),
    );
  }
}

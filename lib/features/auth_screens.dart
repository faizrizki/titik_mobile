import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/app_state.dart';
import '../data/backend.dart';

class _Logo extends StatelessWidget {
  const _Logo({this.size = 40, this.color = TK.g});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Text('titik',
      style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
          color: color,
          height: 1));
}

/// M01 - Splash
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      final s = AppState.I;
      Navigator.pushReplacementNamed(
          context,
          !s.loggedIn
              ? Routes.login
              : s.shiftOpen
                  ? Routes.catalog
                  : Routes.openShift);
    });
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF17664F);
    return Scaffold(
      backgroundColor: bg,
      body: Stack(children: [
        Positioned(
          top: -120,
          right: -140,
          child: Container(
              width: 360,
              height: 360,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFF217D63))),
        ),
        Positioned(
          bottom: -150,
          left: -120,
          child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFF124F3D))),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _Logo(size: 64, color: Colors.white),
              SizedBox(height: 10),
              Text('POS UNTUK USAHA ANDA',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      color: Color(0xFFCDE6DB))),
            ],
          ),
        ),
        Positioned(
          left: 36,
          right: 36,
          bottom: 40,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                  minHeight: 4,
                  color: Color(0xFFB4BE99),
                  backgroundColor: Color(0xFF3F8470)),
            ),
            const SizedBox(height: 14),
            const Text('Menyiapkan data di perangkat…',
                style: TextStyle(fontSize: 14, color: Color(0xFFE3F1EA))),
            const SizedBox(height: 8),
            const Text('Versi 1.0.0',
                style: TextStyle(fontSize: 13, color: Color(0xFF9CC7B6))),
          ]),
        ),
      ]),
    );
  }
}

/// M02 - Masuk kasir
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(text: AppState.demoMode ? 'sari@kopisudut.id' : '');
  final _pass = TextEditingController(text: AppState.demoMode ? 'rahasia123' : '');
  bool _show = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Email dan kata sandi wajib diisi.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = AppState.I;
    try {
      await s.login(_email.text, _pass.text);
      // Unduhan awal katalog (kursor kosong); setelah ini aplikasi bisa offline.
      await s.sync?.syncNow(force: true);
      if (!mounted) return;
      if (s.products.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'Katalog belum terunduh (${s.sync?.lastError ?? 'periksa koneksi'}). '
              'Tekan Masuk lagi saat online.';
        });
        return;
      }
      Navigator.pushReplacementNamed(
          context, s.shiftOpen ? Routes.catalog : Routes.openShift);
    } on SyncException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on BusinessRuleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Screen(
      title: 'Masuk kasir',
      showBack: false,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      bottom: TkButton(_busy ? 'Memproses…' : 'Masuk', onPressed: _busy ? null : _submit),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Logo(),
          const SizedBox(height: 28),
          const Text('Masuk ke kasir',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.5)),
          gap8,
          const Text('Gunakan akun yang dibuat pemilik usaha Anda.',
              style: TextStyle(color: TK.mut)),
          gap24,
          TkField(
              label: 'Email',
              controller: _email,
              keyboard: TextInputType.emailAddress),
          gap16,
          TkField(
            label: 'Kata sandi',
            controller: _pass,
            obscure: !_show,
            suffix: TextButton(
              onPressed: () => setState(() => _show = !_show),
              child: Text(_show ? 'Sembunyikan' : 'Tampilkan',
                  style: const TextStyle(color: TK.g, fontWeight: FontWeight.w600)),
            ),
          ),
          if (_error != null) ...[
            gap8,
            Text(_error!, style: const TextStyle(color: TK.bad, fontSize: 12)),
          ],
          gap12,
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => toast(context, 'Hubungi pemilik usaha untuk reset kata sandi.'),
              child: const Text('Lupa kata sandi?',
                  style: TextStyle(color: TK.g, fontWeight: FontWeight.w600)),
            ),
          ),
          gap12,
          if (AppState.demoMode) ...[
            const TkBanner('Mode demo',
                body: 'Server simulasi di dalam aplikasi. Atur API_BASE_URL untuk backend sungguhan.',
                icon: Icons.science_outlined),
            gap12,
          ],
          const TkBanner('Internet hanya dibutuhkan saat masuk',
              body: 'Setelah itu aplikasi tetap bisa menjual saat koneksi putus.',
              tone: Tone.ok,
              icon: Icons.wifi_off_rounded),
          gap16,
          const Center(
            child: Text(
              'Belum punya akun? Minta pemilik usaha menambahkan Anda di menu Tim & akses.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: TK.mut),
            ),
          ),
        ],
      ),
    );
  }
}

/// M03 - Buka shift
class OpenShiftScreen extends StatefulWidget {
  const OpenShiftScreen({super.key});
  @override
  State<OpenShiftScreen> createState() => _OpenShiftScreenState();
}

class _OpenShiftScreenState extends State<OpenShiftScreen> {
  final _cash = TextEditingController(text: '200000');
  bool _busy = false;

  Future<void> _start(int amount) async {
    setState(() => _busy = true);
    try {
      await AppState.I.openShift(amount);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, Routes.catalog, (r) => false);
    } on BusinessRuleException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final amount = parseRupiah(_cash.text);
    return Screen(
      title: 'Buka shift',
      showBack: false,
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        TkButton('Mulai shift',
            trailing: Icons.arrow_forward_rounded,
            onPressed: amount > 0 && !_busy ? () => _start(amount) : null),
        gap8,
        Text('Shift dicatat ${hhmm(DateTime.now())} WIB · Tersimpan di perangkat',
            style: const TextStyle(fontSize: 12, color: TK.mut)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Halo, ${s.cashierName.split(' ').first}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.5)),
          gap8,
          Text('${tanggalHari(DateTime.now())} · Mulai shift sebelum berjualan.',
              style: const TextStyle(color: TK.mut)),
          gap24,
          const Cap('Cabang'),
          TkCard(
            color: TK.g50,
            child: Row(children: [
              const Icon(Icons.storefront_rounded, color: TK.g),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.branch, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(s.businessName,
                      style: const TextStyle(fontSize: 13, color: TK.mut)),
                ]),
              ),
              const Icon(Icons.check_circle_rounded, color: TK.g),
            ]),
          ),
          gap24,
          TkField(
            label: 'Kas awal di laci',
            controller: _cash,
            prefix: 'Rp ',
            digitsOnly: true,
            keyboard: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          gap12,
          Row(children: [
            for (final v in [100000, 200000, 300000]) ...[
              Expanded(
                child: TkButton(rupiah(v),
                    kind: BtnKind.outline,
                    small: true,
                    onPressed: () => setState(() => _cash.text = '$v')),
              ),
              if (v != 300000) const SizedBox(width: 8),
            ],
          ]),
          gap16,
          const TkBanner('Hitung uang tunai dulu',
              body: 'Angka ini dipakai untuk mencocokkan kas saat shift ditutup.',
              icon: Icons.warning_amber_rounded),
        ],
      ),
    );
  }
}

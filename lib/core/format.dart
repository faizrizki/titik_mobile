/// Uang disimpan sebagai integer rupiah. Tidak pernah double.
String rupiah(int v) {
  final neg = v < 0;
  final s = v.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${neg ? '−' : ''}Rp$buf';
}

int parseRupiah(String s) =>
    int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';

const _bulan = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
];
String tanggal(DateTime t) => '${t.day} ${_bulan[t.month - 1]} ${t.year}';

/// Tarif dalam basis poin -> teks persen (1100 -> "11", 250 -> "2,5").
String pctLabel(int bps) {
  if (bps % 100 == 0) return '${bps ~/ 100}';
  final s = (bps / 100).toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  return s.replaceAll('.', ',');
}

const _hari = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

/// "Rabu, 18 Nov 2026"
String tanggalHari(DateTime t) => '${_hari[t.weekday - 1]}, ${tanggal(t)}';

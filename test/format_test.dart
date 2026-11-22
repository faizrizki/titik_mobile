import 'package:flutter_test/flutter_test.dart';
import 'package:titik_mobile/core/format.dart';

void main() {
  test('rupiah memformat ribuan dan negatif', () {
    expect(rupiah(18000), 'Rp18.000');
    expect(rupiah(1100000), 'Rp1.100.000');
    expect(rupiah(0), 'Rp0');
    expect(rupiah(-10000), '−Rp10.000');
  });
  test('parseRupiah mengabaikan non-angka', () {
    expect(parseRupiah('Rp 50.000'), 50000);
  });
}

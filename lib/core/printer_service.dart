
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import 'receipt.dart';

class PrinterDevice {
  const PrinterDevice(this.name, this.address);
  final String name;
  final String address;
}

/// Transport cetak. Di perangkat memakai Bluetooth; dapat diganti di tes.
abstract class PrinterTransport {
  Future<bool> bluetoothOn();
  Future<List<PrinterDevice>> paired();
  Future<bool> connect(String address);
  Future<bool> write(Uint8List bytes);
  Future<bool> connected();
  Future<void> disconnect();
}

class BluetoothTransport implements PrinterTransport {
  @override
  Future<bool> bluetoothOn() => PrintBluetoothThermal.bluetoothEnabled;
  @override
  Future<List<PrinterDevice>> paired() async => [
        for (final b in await PrintBluetoothThermal.pairedBluetooths)
          PrinterDevice(b.name, b.macAdress)
      ];
  @override
  Future<bool> connect(String address) =>
      PrintBluetoothThermal.connect(macPrinterAddress: address);
  @override
  Future<bool> write(Uint8List bytes) => PrintBluetoothThermal.writeBytes(bytes);
  @override
  Future<bool> connected() => PrintBluetoothThermal.connectionStatus;
  @override
  Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
  }
}

/// Pengaturan dan pencetakan struk (US-05). Bila printer gagal, struk PDF
/// dapat dibagikan sebagai cadangan.
class PrinterService extends ChangeNotifier {
  PrinterService({PrinterTransport? transport}) : transport = transport ?? BluetoothTransport();

  static PrinterService I = PrinterService();

  final PrinterTransport transport;
  PrinterDevice? device;
  int paperMm = 58;
  bool autoPrint = true;
  bool showCashier = true;
  String? lastError;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    paperMm = p.getInt('printer.paper') ?? 58;
    autoPrint = p.getBool('printer.auto') ?? true;
    showCashier = p.getBool('printer.cashier') ?? true;
    final name = p.getString('printer.name');
    final addr = p.getString('printer.addr');
    if (name != null && addr != null) device = PrinterDevice(name, addr);
    notifyListeners();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('printer.paper', paperMm);
    await p.setBool('printer.auto', autoPrint);
    await p.setBool('printer.cashier', showCashier);
    if (device != null) {
      await p.setString('printer.name', device!.name);
      await p.setString('printer.addr', device!.address);
    }
    notifyListeners();
  }

  ReceiptOptions options(String business, String branch) => ReceiptOptions(
        paperMm: paperMm,
        showCashier: showCashier,
        businessName: business,
        branchName: branch,
      );

  Future<bool> connectTo(PrinterDevice d) async {
    lastError = null;
    final ok = await transport.connect(d.address);
    if (ok) {
      device = d;
      await save();
    } else {
      lastError = 'Tidak bisa terhubung ke ${d.name}. Pastikan printer menyala.';
    }
    notifyListeners();
    return ok;
  }

  Future<bool> _send(Uint8List bytes) async {
    lastError = null;
    if (device == null) {
      lastError = 'Belum ada printer dipilih.';
      notifyListeners();
      return false;
    }
    try {
      if (!await transport.connected() && !await transport.connect(device!.address)) {
        lastError = 'Printer ${device!.name} tidak terhubung.';
        return false;
      }
      final ok = await transport.write(bytes);
      if (!ok) lastError = 'Gagal mengirim ke printer.';
      return ok;
    } catch (e) {
      lastError = 'Gagal mencetak: $e';
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> printReceipt(Txn t, String business, String branch) =>
      _send(buildEscPos(t, options(business, branch)));

  Future<bool> printTestPage(String business, String branch) =>
      _send(buildTestPage(options(business, branch)));

  Future<bool> printShiftReport(Shift s, String business, String branch) =>
      _send(buildShiftReport(s, options(business, branch)));

  /// Cadangan tanpa printer: bagikan struk sebagai PDF.
  Future<void> sharePdf(Txn t, String business, String branch) async {
    final bytes = await buildReceiptPdf(t, options(business, branch));
    await Printing.sharePdf(bytes: bytes, filename: 'struk-${t.id}.pdf');
  }
}

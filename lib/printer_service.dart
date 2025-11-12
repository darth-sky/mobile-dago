// File: lib/printer_service.dart
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class PrinterService {
  BluetoothDevice? _printer;

  // Fungsi untuk meminta semua izin
  Future<void> requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  // Fungsi untuk mencari printer Anda
  Future<void> startScan() async {
    print("Mulai memindai printer...");
    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth tidak didukung oleh perangkat ini");
      return;
    }
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
       print("Bluetooth mati, mencoba menyalakan...");
       await FlutterBluePlus.turnOn();
    }
    
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        
        // ** INI SUDAH ANDA GANTI DENGAN BENAR (RPP02) **
        if (r.device.platformName == 'RPP02') { 
          _printer = r.device;
          FlutterBluePlus.stopScan();
          _printer?.connect();
          print("Printer ditemukan dan terhubung: ${r.device.platformName}");
          break;
        }
      }
    });
  }

  // Fungsi yang akan dipanggil oleh React
  Future<void> printReceipt(Map<String, dynamic> dataStruk) async {
    if (_printer == null) {
      print("Error: Printer tidak terhubung. Mencoba memindai ulang...");
      startScan(); // Coba cari lagi
      return;
    }
    
    // Cek apakah perangkat masih terhubung
    try {
      // Kita gunakan 'await' untuk memastikan koneksi selesai
      await _printer!.connect(); 
    } catch (e) {
      if (e.toString().contains('already connected')) {
         // Ini wajar, tidak apa-apa
      } else {
         print("Gagal menyambung ulang: $e");
      }
    }


    print("Menerima data dari React: $dataStruk");

    // 1. Format data JSON dari React menjadi struk
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    bytes += generator.text('Struk Kasir Dago', styles: PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text(dataStruk['kasir'] ?? 'Kasir', styles: PosStyles(align: PosAlign.center));
    bytes += generator.hr();

    if (dataStruk['items'] != null) {
      for (var item in (dataStruk['items'] as List)) {
        bytes += generator.row([
          PosColumn(text: "${item['qty']}x ${item['name']}", width: 8),
          PosColumn(text: "Rp ${item['price']}", width: 4, styles: PosStyles(align: PosAlign.right)),
        ]);
      }
    }

    bytes += generator.hr();
    bytes += generator.text('Total: Rp ${dataStruk['total']}', styles: PosStyles(align: PosAlign.right, bold: true));
    bytes += generator.feed(2);
    bytes += generator.cut();

    // 2. PERBAIKAN: Kirim 'bytes' ke printer
    try {
      print("Mencari services...");

      // --- PERBAIKAN UTAMA DI SINI ---
      // Dapatkan MTU saat ini dari perangkat (di log Anda 240)
      // Kurangi 3 untuk overhead protokol (batas kita jadi 237)
      int chunkSize = (await _printer!.mtu.first) - 3;
      print("MTU size: ${await _printer!.mtu.first}, using chunk size: $chunkSize");

      // Safety check: jika MTU aneh, set default
      if (chunkSize <= 0) {
         chunkSize = 237; // Fallback ke nilai yang kita lihat di log
      }
      // --- AKHIR PERBAIKAN UTAMA ---

      List<BluetoothService> services = await _printer!.discoverServices();
      
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.writeWithoutResponse || characteristic.properties.write) {
            print("Menemukan characteristic yang bisa write!");
            print("Mengirim data ${bytes.length} bytes ke printer...");
            
            // Gunakan 'chunkSize' yang baru (237)
            for (int i = 0; i < bytes.length; i += chunkSize) {
              // Potong data:
              // Potongan 1: 0 s/d 237
              // Potongan 2: 237 s/d 243
              List<int> chunk = bytes.sublist(i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize);
              
              await characteristic.write(chunk, withoutResponse: true);
              print("Mengirim chunk ${chunk.length} bytes...");
            }
            
            print("Data berhasil dikirim!");
            return; // Keluar setelah berhasil mengirim
          }
        }
      }
      print("Error: Tidak ditemukan characteristic yang bisa write.");
    } catch (e) {
      print("Error saat mengirim ke printer: $e");
    }
  }
}
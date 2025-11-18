// File: lib/printer_service.dart
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart'; // Import intl untuk format tanggal

class PrinterService {
  static BluetoothDevice? _printer;

  Future<void> requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Stream<List<ScanResult>> scanForPrinters() {
    print("Mulai memindai printer...");
    FlutterBluePlus.isSupported.then((isSupported) {
      if (isSupported) {
        FlutterBluePlus.adapterState.first.then((state) {
          if (state != BluetoothAdapterState.on) {
            FlutterBluePlus.turnOn();
          }
        });
      }
    });
    FlutterBluePlus.startScan(timeout: Duration(seconds: 5));
    return FlutterBluePlus.scanResults;
  }
  
  Future<void> connectToPrinter(BluetoothDevice device) async {
    print("Mencoba terhubung ke: ${device.platformName}");
    await device.connect();
    _printer = device; 
    FlutterBluePlus.stopScan();
    print("Printer ditemukan dan terhubung: ${device.platformName}");
  }
  
  static BluetoothDevice? getConnectedPrinter() {
    return _printer;
  }
  
  Future<void> disconnectPrinter() async {
    if (_printer == null) {
      print("Tidak ada printer yang terhubung.");
      return;
    }
    try {
      print("Memutuskan sambungan dari: ${_printer!.platformName}");
      await _printer!.disconnect();
    } catch (e) {
      print("Error saat disconnect: $e");
    } finally {
      _printer = null; 
      print("Printer terputus.");
    }
  }

  // --- FUNGSI UTAMA (FORMAT STRUK) ---
  Future<void> printReceipt(Map<String, dynamic> dataStruk) async {
    if (_printer == null) {
      print("Error: Printer belum dipilih. Panggil 'flutterShowPrinterList' dari React.");
      return;
    }
    
    try {
      await _printer!.connect(); 
    } catch (e) {
      if (!e.toString().contains('already connected')) {
         print("Gagal menyambung ulang: $e");
      }
    }

    print("Menerima data dari React: $dataStruk");

    // 1. Format data JSON
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];
    
    // --- Ambil data dari React ---
    double subtotal = (dataStruk['subtotal'] ?? 0.0).toDouble();
    double tax = (dataStruk['tax'] ?? 0.0).toDouble();
    double discount = (dataStruk['discount'] ?? 0.0).toDouble();
    double total = (dataStruk['total'] ?? 0.0).toDouble();
    double tunai = (dataStruk['tunai'] ?? 0.0).toDouble();
    double kembali = (dataStruk['kembali'] ?? 0.0).toDouble();
    String paymentMethod = (dataStruk['paymentMethod'] ?? 'N/A').toString().toUpperCase();

    // Format Tanggal (dataStruk['time'] adalah ISOString)
    final String formattedDate = dataStruk['time'] != null
        ? DateFormat('dd/MM/yy HH:mm:ss').format(DateTime.parse(dataStruk['time']))
        : DateFormat('dd/MM/yy HH:mm:ss').format(DateTime.now());

    // --- Header Struk ---
    bytes += generator.text('DagoEng', styles: PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.text('Creative Hub & Coffee Lab', styles: PosStyles(align: PosAlign.center, height: PosTextSize.size2));
    bytes += generator.feed(1);
    bytes += generator.text('Kasir    : ${dataStruk['cashier'] ?? 'N/A'}', styles: PosStyles(align: PosAlign.left));
    bytes += generator.text('Pelanggan: ${dataStruk['customer'] ?? 'Guest'}', styles: PosStyles(align: PosAlign.left));
    bytes += generator.text('Lokasi   : ${dataStruk['location'] ?? '-'}', styles: PosStyles(align: PosAlign.left));
    bytes += generator.text('ID Trans : #${dataStruk['id'] ?? 'N/A'}', styles: PosStyles(align: PosAlign.left));
    bytes += generator.text('Waktu    : $formattedDate', styles: PosStyles(align: PosAlign.left));
    bytes += generator.hr();

    // --- Loop Item F&B ---
    List<dynamic> fnbItems = dataStruk['items'] ?? [];
    if (fnbItems.isNotEmpty) {
      // bytes += generator.text('--- Item F&B ---', styles: PosStyles(align: PosAlign.center));
      for (var item in fnbItems) {
        int qty = (item['qty'] ?? 1).toInt();
        double price = (item['price'] ?? 0.0).toDouble(); // Ini harga satuan
        double totalItemPrice = price * qty;
        
        // Baris 1: Nama Makanan
        bytes += generator.text('${item['name'] ?? 'Item'}', styles: PosStyles(align: PosAlign.left, bold: true));
        
        // Baris 2: Qty x Harga (kiri) dan Total (kanan)
        bytes += generator.row([
          PosColumn(text: "  ${qty} x ${price.toInt()}", width: 6, styles: PosStyles(align: PosAlign.left)),
          PosColumn(text: "Rp ${totalItemPrice.toInt()}", width: 6, styles: PosStyles(align: PosAlign.right)),
        ]);
        
        // Baris 3: Note (jika ada)
        if (item['note'] != null && item['note'].isNotEmpty) {
          bytes += generator.text('  (Note: ${item['note']})', styles: PosStyles(align: PosAlign.left, bold: false));
        }
      }
    }

    // --- Loop Booking ---
    List<dynamic> bookingItems = dataStruk['bookings'] ?? [];
    if (bookingItems.isNotEmpty) {
      // bytes += generator.text('--- Booking Ruangan ---', styles: PosStyles(align: PosAlign.center));
      for (var booking in bookingItems) {
        var bookingData = booking['bookingData'] ?? {};
        double price = (booking['price'] ?? 0.0).toDouble(); // Ini adalah harga_paket
        double duration = (bookingData['durasi_jam'] ?? 0.0).toDouble();
        
        bytes += generator.text('${booking['name']}', styles: PosStyles(align: PosAlign.left, bold: true));
        bytes += generator.row([
          PosColumn(text: "  ${duration.toInt()} Jam", width: 6, styles: PosStyles(align: PosAlign.left)),
          PosColumn(text: "Rp ${price.toInt()}", width: 6, styles: PosStyles(align: PosAlign.right)),
        ]);
        
        String startTime = "${bookingData['waktu_mulai_jam']}:00";
        String endTime = "${(bookingData['waktu_mulai_jam'] ?? 0) + duration.toInt()}:00";
        bytes += generator.text('  Waktu: $startTime - $endTime', styles: PosStyles(align: PosAlign.left));
      }
    }

    // --- PERBAIKAN: Layout Summary Sesuai Permintaan ---
    bytes += generator.hr();
    
    // Blok 1: Subtotal, Tax, Disc (Sesuai contoh Anda)
    bytes += generator.row([
      PosColumn(text: "Sub Total", width: 6, styles: PosStyles(align: PosAlign.left)),
      PosColumn(text: "Rp ${subtotal.toInt()}", width: 6, styles: PosStyles(align: PosAlign.right)),
    ]);
    
    if (tax > 0) {
      bytes += generator.row([
        PosColumn(text: "Tax", width: 6, styles: PosStyles(align: PosAlign.left)),
        PosColumn(text: "Rp ${tax.toInt()}", width: 6, styles: PosStyles(align: PosAlign.right)),
      ]);
    }
    
    if (discount > 0) {
      bytes += generator.row([
        PosColumn(text: "Disc", width: 6, styles: PosStyles(align: PosAlign.left)),
        PosColumn(text: "Rp ${discount.toInt()}", width: 6, styles: PosStyles(align: PosAlign.right)),
      ]);
    }

    // Pemisah (Sesuai contoh Anda)
    bytes += generator.hr(); 

    // Blok 2: Total, Tunai, Kembali (Mengikuti style yang sama)
    bytes += generator.row([
      // Total dibuat bold untuk penekanan, tapi ukuran font normal
      PosColumn(text: "Total", width: 6, styles: PosStyles(align: PosAlign.left, bold: true)),
      PosColumn(text: "Rp ${total.toInt()}", width: 6, styles: PosStyles(align: PosAlign.right, bold: true)),
    ]);
    // bytes += generator.feed(1); // Beri spasi sedikit

    // Metode Pembayaran (style normal seperti Sub Total)
    if (paymentMethod == 'CASH') {
      bytes += generator.row([
        PosColumn(text: "Tunai", width: 6, styles: PosStyles(align: PosAlign.left)),
        PosColumn(text: "Rp ${tunai.toInt()}", width: 6, styles: PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(text: "Kembali", width: 6, styles: PosStyles(align: PosAlign.left)),
        PosColumn(text: "Rp ${kembali.toInt()}", width: 6, styles: PosStyles(align: PosAlign.right)),
      ]);
    } else {
      bytes += generator.row([
        PosColumn(text: "Bayar ($paymentMethod)", width: 6, styles: PosStyles(align: PosAlign.left)),
        PosColumn(text: "Rp ${total.toInt()}", width: 6, styles: PosStyles(align: PosAlign.right)),
      ]);
    }
    // --- AKHIR SUMMARY BARU ---
    bytes += generator.hr(); 
    bytes += generator.feed(2);
    bytes += generator.cut();

    // 2. Kirim 'bytes' ke printer (logika chunk tidak berubah)
    try {
      print("Mencari services...");
      int chunkSize = (await _printer!.mtu.first) - 3;
      if (chunkSize <= 0) { chunkSize = 237; } 

      List<BluetoothService> services = await _printer!.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.writeWithoutResponse || characteristic.properties.write) {
            print("Menemukan characteristic yang bisa write!");
            print("Mengirim data ${bytes.length} bytes ke printer...");
            
            for (int i = 0; i < bytes.length; i += chunkSize) {
              List<int> chunk = bytes.sublist(i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize);
              await characteristic.write(chunk, withoutResponse: true);
            }
            
            print("Data berhasil dikirim!");
            return; 
          }
        }
      }
      print("Error: Tidak ditemukan characteristic yang bisa write.");
    } catch (e) {
      print("Error saat mengirim ke printer: $e");
    }
  }
}
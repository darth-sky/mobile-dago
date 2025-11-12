// File: lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// Ganti 'flutter_application_1' dengan nama proyek Anda jika berbeda
import 'package:flutter_application_1/printer_service.dart'; 

// Inisialisasi service printer
final PrinterService _printerService = PrinterService();

Future<void> main() async {
  // Pastikan semua widget siap sebelum menjalankan
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(KasirApp());
}

class KasirApp extends StatelessWidget {
  const KasirApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: WebViewScreen());
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({Key? key}) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _webViewController;
  final String reactUrl = "http://172.16.81.237:5173";

  @override
  void initState() {
    super.initState();
    _requestHardwareAccess();
  }

  // Buat fungsi untuk memanggil izin
  Future<void> _requestHardwareAccess() async {
    await _printerService.requestPermissions();
    _printerService.startScan();
  }

  // -- FUNGSI BARU UNTUK MENYUNTIKKAN JEMBATAN --
  // Kita buat fungsi terpisah agar bisa dipanggil dari banyak tempat
  void _injectBridge(InAppWebViewController controller) {
    print("Menyuntikkan jembatan 'flutterPrintHandler'...");
    
    controller.addJavaScriptHandler(
      handlerName: 'flutterPrintHandler',
      callback: (args) {
        print("JEMBATAN BERHASIL DIPANGGIL DARI REACT!");
        if (args.isNotEmpty) {
          Map<String, dynamic> dataStruk = Map<String, dynamic>.from(args[0]);
          _printerService.printReceipt(dataStruk);
        }
      },
    );
    print("Jembatan berhasil disuntikkan.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          // 1. MUAT URL APLIKASI REACT ANDA
          initialUrlRequest: URLRequest(url: WebUri(reactUrl)),

          // 2. TAMBAHKAN OPSI INI
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            // Tambahan: Izinkan HMR
            allowsInlineMediaPlayback: true,
          ),

          onWebViewCreated: (controller) {
            _webViewController = controller;
            // Coba suntik di sini (pertama)
            _injectBridge(controller);
          },

          onLoadStop: (controller, url) {
            print("Halaman selesai dimuat: $url");
            // Coba suntik di sini (kedua, untuk HMR/navigasi)
            _injectBridge(controller);
          },

          // PERBAIKAN UTAMA: Tambahkan 'onProgressChanged'
          // Ini akan berjalan setiap kali progress halaman berubah
          onProgressChanged: (controller, progress) {
            // Saat halaman selesai 100%
            if (progress == 100) {
              print("Progress 100%, menyuntikkan jembatan...");
              // Coba suntik di sini lagi (ketiga, sebagai cadangan)
              _injectBridge(controller);
            }
          },

          onConsoleMessage: (controller, consoleMessage) {
            // Ini akan mencetak log dari React ke console Flutter
            print("Konsol WebView: ${consoleMessage.message}");
          },
        ),
      ),
    );
  }
}
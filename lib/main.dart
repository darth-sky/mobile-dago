// File: lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// Ganti 'flutter_application_1' dengan nama proyek Anda
import 'package:flutter_application_1/printer_service.dart';
import 'package:flutter_application_1/printer_list_page.dart'; 

// Inisialisasi service printer
final PrinterService _printerService = PrinterService();

Future<void> main() async {
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
  final String reactUrl = "http://172.16.81.237:5173"; // Pastikan IP & port Anda benar

  @override
  void initState() {
    super.initState();
    _printerService.requestPermissions();
  }

  void _injectBridge(InAppWebViewController controller) {
    // Jembatan 'flutterPrintHandler' (Tidak berubah)
    print("Menyuntikkan jembatan 'flutterPrintHandler'...");
    controller.addJavaScriptHandler(
      handlerName: 'flutterPrintHandler',
      callback: (args) {
        print("JEMBATAN 'flutterPrintHandler' DIPANGGIL DARI REACT!");
        if (args.isNotEmpty) {
          Map<String, dynamic> dataStruk = Map<String, dynamic>.from(args[0]);
          _printerService.printReceipt(dataStruk);
        }
      },
    );

    // Jembatan 'flutterShowPrinterList' (Tidak berubah)
    print("Menyuntikkan jembatan 'flutterShowPrinterList'...");
    controller.addJavaScriptHandler(
        handlerName: 'flutterShowPrinterList',
        callback: (args) async {
          print("JEMBATAN 'flutterShowPrinterList' DIPANGGIL DARI REACT!");
          final String? selectedName = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PrinterListPage(printerService: _printerService),
            ),
          );
          if (selectedName != null) {
            print("Mengirim nama printer '$selectedName' kembali ke React...");
            _webViewController?.evaluateJavascript(
              source: 'window.updatePrinterName("$selectedName")'
            );
          }
        });
        
    // Jembatan 'flutterGetConnectedPrinter' (Tidak berubah)
    print("Menyuntikkan jembatan 'flutterGetConnectedPrinter'...");
    controller.addJavaScriptHandler(
      handlerName: 'flutterGetConnectedPrinter',
      callback: (args) {
        var printer = PrinterService.getConnectedPrinter();
        if(printer != null) {
          _webViewController?.evaluateJavascript(
            source: 'window.updatePrinterName("${printer.platformName}")'
          );
        }
      }
    );

    // --- JEMBATAN BARU UNTUK DISCONNECT ---
    print("Menyuntikkan jembatan 'flutterDisconnectPrinter'...");
    controller.addJavaScriptHandler(
      handlerName: 'flutterDisconnectPrinter',
      callback: (args) async {
        print("JEMBATAN 'flutterDisconnectPrinter' DIPANGGIL DARI REACT!");
        await _printerService.disconnectPrinter();
        
        // Kirim status 'null' kembali ke React untuk update UI
        _webViewController?.evaluateJavascript(
          source: 'window.updatePrinterName(null)'
        );
      }
    );
    // --- AKHIR JEMBATAN BARU ---

    print("Semua jembatan berhasil disuntikkan.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: InAppWebView(
          // ... (semua properti WebView tidak berubah) ...
          initialUrlRequest: URLRequest(url: WebUri(reactUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            allowsInlineMediaPlayback: true,
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;
          },
          onLoadStop: (controller, url) {
            print("Halaman selesai dimuat: $url");
            _injectBridge(controller); 
          },
          onProgressChanged: (controller, progress) {
            if (progress == 100) {
              _injectBridge(controller); 
            }
          },
          onConsoleMessage: (controller, consoleMessage) {
            print("Konsol WebView: ${consoleMessage.message}");
          },
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:client/core/providers/database_providers.dart';
import 'package:client/core/providers/locale_provider.dart';
import 'package:client/core/utils/formatters.dart';
import 'package:client/features/checkout/providers/cart_provider.dart';
import 'package:client/features/inventory/widgets/product_form_modal.dart';
import 'package:client/l10n/app_localizations.dart';

class BarcodeScannerScreen extends ConsumerStatefulWidget {
  /// When [isPickMode] is true, the screen closes and returns the scanned barcode string
  /// upon first successful detection instead of adding products to the cart.
  final bool isPickMode;

  const BarcodeScannerScreen({
    super.key,
    this.isPickMode = false,
  });

  /// Opens the continuous scanner for POS checkout cart building.
  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(isPickMode: false),
      ),
    );
  }

  /// Opens the scanner in single-scan pick mode and returns the scanned barcode string.
  static Future<String?> scanBarcode(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(isPickMode: true),
      ),
    );
  }

  @override
  ConsumerState<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  late final MobileScannerController _controller;

  String? _lastScannedBarcode;
  DateTime? _lastScannedTime;

  // Active status feedback to display on the scanner overlay
  String? _statusMessage;
  bool _statusIsSuccess = true;
  String? _unknownBarcode;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcodeDetected(BarcodeCapture capture) async {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;
    final barcode = rawValue.trim();

    final now = DateTime.now();
    // Debounce duplicate scans of the exact same barcode within 1.5 seconds
    if (_lastScannedBarcode == barcode &&
        _lastScannedTime != null &&
        now.difference(_lastScannedTime!) < const Duration(milliseconds: 1500)) {
      return;
    }

    _lastScannedBarcode = barcode;
    _lastScannedTime = now;

    // Haptic & Sound Feedback
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    // If running in pick mode (e.g. from Add Product modal), return the scanned barcode immediately
    if (widget.isPickMode) {
      Navigator.of(context).pop(barcode);
      return;
    }

    final db = ref.read(databaseProvider);
    final isAmharic = ref.read(localeProvider.notifier).isAmharic;
    final l10n = AppLocalizations.of(context);

    // Lookup product in local Drift SQLite
    final product = await db.getProductByBarcode(barcode);

    if (!mounted) return;

    if (product != null) {
      // Product exists: Add to cart
      ref.read(cartProvider.notifier).addProduct(product);

      final productName = isAmharic ? product.nameAm : product.nameEn;
      final priceStr = CurrencyFormatter.format(product.sellingPrice, isAmharic: isAmharic);

      setState(() {
        _statusMessage = '✓ $productName ($priceStr)';
        _statusIsSuccess = true;
        _unknownBarcode = null;
      });
    } else {
      // Product not found in local catalog
      HapticFeedback.heavyImpact();
      setState(() {
        _statusMessage = '${l10n?.barcodeNotFound ?? 'Barcode not found'}: $barcode';
        _statusIsSuccess = false;
        _unknownBarcode = barcode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;
    final cart = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Live Camera Feed
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcodeDetected,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined, color: Colors.white70, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        l10n?.cameraPermissionRequired ??
                            'Camera permission is required to scan barcodes.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // 2. Targeting Overlay & Reticle
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ScannerOverlayPainter(),
              ),
            ),
          ),

          // 3. Top Action Bar: Torch, Camera Flip, Close
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Row(
                    children: [
                      ValueListenableBuilder<MobileScannerState>(
                        valueListenable: _controller,
                        builder: (context, state, child) {
                          final isTorchOn = state.torchState == TorchState.on;
                          return IconButton(
                            icon: Icon(
                              isTorchOn ? Icons.flash_on : Icons.flash_off,
                              color: isTorchOn ? Colors.amber : Colors.white,
                              size: 26,
                            ),
                            onPressed: () => _controller.toggleTorch(),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 26),
                        onPressed: () => _controller.switchCamera(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 4. Center Guidance Text
          Positioned(
            top: MediaQuery.of(context).size.height * 0.22,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.isPickMode
                      ? (l10n?.scanBarcodePrompt ?? 'Scan Barcode')
                      : (l10n?.alignBarcodeWithinFrame ?? 'Align barcode within the target frame'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // 5. Dynamic Scan Status Toast / Action Banner
          if (_statusMessage != null && !widget.isPickMode)
            Positioned(
              bottom: 110,
              left: 16,
              right: 16,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _statusIsSuccess
                      ? const Color(0xFF1B5E20).withValues(alpha: 0.95)
                      : const Color(0xFFB71C1C).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusIsSuccess ? Icons.check_circle : Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!_statusIsSuccess && _unknownBarcode != null) ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final code = _unknownBarcode;
                          ProductFormModal.show(context, initialBarcode: code);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFB71C1C),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          l10n?.addNewProductWithBarcode ?? 'Add Item',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // 6. Bottom Continuous Cart Counter & Finish Bar (checkout mode only)
          if (!widget.isPickMode)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  border: const Border(top: BorderSide(color: Colors.white24, width: 0.5)),
                ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l10n?.itemsScanned ?? 'Items in cart'}: ${cart.totalItemCount}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${l10n?.subtotal ?? 'Subtotal'}: ${CurrencyFormatter.format(cart.subtotal, isAmharic: isAmharic)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.check, size: 20),
                    label: Text(
                      l10n?.scannerDone ?? 'Done',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter to draw a darkened background with a clear reticle scanning cutout
class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanWindowWidth = size.width * 0.78;
    final scanWindowHeight = size.height * 0.32;
    final left = (size.width - scanWindowWidth) / 2;
    final top = (size.height - scanWindowHeight) / 2 - 30;

    final scanRect = Rect.fromLTWH(left, top, scanWindowWidth, scanWindowHeight);
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16)));

    final overlayPath = Path.combine(PathOperation.difference, backgroundPath, cutoutPath);
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(overlayPath, overlayPaint);

    // Draw reticle border corners
    final cornerPaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 26.0;
    const r = 16.0;

    // Top-Left
    canvas.drawPath(
      Path()
        ..moveTo(left, top + cornerLength)
        ..lineTo(left, top + r)
        ..arcToPoint(Offset(left + r, top), radius: const Radius.circular(r))
        ..lineTo(left + cornerLength, top),
      cornerPaint,
    );

    // Top-Right
    final right = left + scanWindowWidth;
    canvas.drawPath(
      Path()
        ..moveTo(right - cornerLength, top)
        ..lineTo(right - r, top)
        ..arcToPoint(Offset(right, top + r), radius: const Radius.circular(r))
        ..lineTo(right, top + cornerLength),
      cornerPaint,
    );

    // Bottom-Left
    final bottom = top + scanWindowHeight;
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - cornerLength)
        ..lineTo(left, bottom - r)
        ..arcToPoint(Offset(left + r, bottom), radius: const Radius.circular(r))
        ..lineTo(left + cornerLength, bottom),
      cornerPaint,
    );

    // Bottom-Right
    canvas.drawPath(
      Path()
        ..moveTo(right - cornerLength, bottom)
        ..lineTo(right - r, bottom)
        ..arcToPoint(Offset(right, bottom - r), radius: const Radius.circular(r))
        ..lineTo(right, bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/pdf_export.dart';

void main() {
  test('seller report totals remain separated by currency', () {
    final totals = sellerReportTotalsByCurrency([
      const SellerReportShop(
        name: 'SAR Shop One',
        totalPairsSold: 12,
        totalRevenue: 100,
        outstandingBalance: 40,
        currency: 'sar',
      ),
      const SellerReportShop(
        name: 'PKR Shop',
        totalPairsSold: 24,
        totalRevenue: 200,
        outstandingBalance: 80,
        currency: 'PKR',
      ),
      const SellerReportShop(
        name: 'SAR Shop Two',
        totalPairsSold: 6,
        totalRevenue: 50,
        outstandingBalance: 20,
        currency: 'SAR',
      ),
    ]);

    expect(totals.keys, ['SAR', 'PKR']);
    expect(totals['SAR']!.revenue, 150);
    expect(totals['SAR']!.outstanding, 60);
    expect(totals['PKR']!.revenue, 200);
    expect(totals['PKR']!.outstanding, 80);
  });
}

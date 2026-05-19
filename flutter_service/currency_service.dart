import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Replace with your actual GitHub username.
const _githubUser = 'YOUR_USERNAME';
const _cdnUrl =
    'https://cdn.jsdelivr.net/gh/$_githubUser/currency-rates-cache@main/rates.json';

const _cacheMaxAgeHours = 24;

class CurrencyRates {
  final String base;
  final String date;
  final Map<String, double> rates;

  const CurrencyRates({
    required this.base,
    required this.date,
    required this.rates,
  });

  factory CurrencyRates.fromJson(Map<String, dynamic> json) {
    final rawRates = json['rates'] as Map<String, dynamic>;
    return CurrencyRates(
      base: json['base'] as String,
      date: json['date'] as String,
      rates: rawRates.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

class CurrencyService {
  static const _cacheFileName = 'rates.json';

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  Future<CurrencyRates> getRates() async {
    final file = await _cacheFile();

    if (await file.exists()) {
      final modified = await file.lastModified();
      final age = DateTime.now().difference(modified);

      if (age.inHours < _cacheMaxAgeHours) {
        return _parseFile(file);
      }
    }

    // Cache is missing or stale — fetch from CDN.
    try {
      return await _fetchAndCache(file);
    } catch (_) {
      // Network failed: fall back to whatever is cached, even if stale.
      if (await file.exists()) {
        return _parseFile(file);
      }
      rethrow;
    }
  }

  Future<CurrencyRates> _parseFile(File file) async {
    final contents = await file.readAsString();
    return CurrencyRates.fromJson(jsonDecode(contents) as Map<String, dynamic>);
  }

  Future<CurrencyRates> _fetchAndCache(File file) async {
    final response = await http.get(Uri.parse(_cdnUrl));

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch rates: HTTP ${response.statusCode}',
        uri: Uri.parse(_cdnUrl),
      );
    }

    await file.writeAsString(response.body);
    return CurrencyRates.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Converts [amount] from [fromCurrency] to [toCurrency].
  double convert({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
    required CurrencyRates rates,
  }) {
    if (fromCurrency == rates.base) {
      return amount * (rates.rates[toCurrency] ?? 1.0);
    }

    // Convert to base first, then to target.
    final toBase = amount / (rates.rates[fromCurrency] ?? 1.0);
    return toBase * (rates.rates[toCurrency] ?? 1.0);
  }
}

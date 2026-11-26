/// Store identifiers. These strings are load-bearing: they are shared between
/// Dart, the Kotlin Xsolla bridge, RevenueCat and both app stores.
abstract final class StoreSkus {
  // ---------------------------------------------------------------- products
  static const String coins100 = 'coins_100';
  static const String coins500 = 'coins_500';
  static const String coins1500 = 'coins_1500';
  static const String multimediaPack = 'multimedia_pack';

  static const int coins100Amount = 100;
  static const int coins500Amount = 500;
  static const int coins1500Amount = 1500;

  static const List<CoinPack> coinPacks = <CoinPack>[
    CoinPack(
      sku: coins100,
      coins: coins100Amount,
      title: 'Starter Pack',
      tag: 'STARTER',
      blurb: 'Enough for a premium choice and a decryption boost.',
    ),
    CoinPack(
      sku: coins500,
      coins: coins500Amount,
      title: 'Relay Pack',
      tag: 'MOST POPULAR',
      blurb: 'Unlock every premium choice across a full episode.',
    ),
    CoinPack(
      sku: coins1500,
      coins: coins1500Amount,
      title: 'Deep Water Pack',
      tag: 'BEST VALUE',
      blurb: 'Never think about coins again this season.',
    ),
  ];

  static int? coinsForSku(String sku) => switch (sku) {
        coins100 => coins100Amount,
        coins500 => coins500Amount,
        coins1500 => coins1500Amount,
        _ => null,
      };

  // ------------------------------------------------------- RevenueCat config
  static const String revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: '',
  );

  /// Store-specific RevenueCat keys, selected by installer package.
  static const Map<String, String> installerKeys = <String, String>{
    'com.amazon.venezia': 'amzn_XUdUqitSlOeKWirdenGzoprIiQm',
    'com.sec.android.app.samsungapps': 'galx_iMWOSEVoUdbxVRxYTccusGpkLlH',
  };

  // --------------------------------------------------------------- Xsolla
  static const int xsollaProjectId = 322198;
  static const String xsollaLoginId = '49611eb4-b8eb-4b52-95b6-0d0529436a0e';
  static const String xsollaChannel = 'com.eyeswatchinggames.no_tide_back/xsolla';

  // --------------------------------------------------------------- Firestore
  static const String playersCollection = 'players';
}

class CoinPack {
  const CoinPack({
    required this.sku,
    required this.coins,
    required this.title,
    required this.tag,
    required this.blurb,
  });

  final String sku;
  final int coins;
  final String title;
  final String tag;
  final String blurb;
}

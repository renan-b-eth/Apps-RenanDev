import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/percent_indicator.dart';

// --- DADOS: TAXAS MÉDIAS POR ESTADO (2025) ---
const Map<String, double> usStatesTaxRates = {
  'Alabama': 9.22, 'Alaska': 1.76, 'Arizona': 8.40, 'Arkansas': 9.51,
  'California': 8.82, 'Colorado': 7.77, 'Connecticut': 6.35, 'Delaware': 0.0,
  'Florida': 7.01, 'Georgia': 7.35, 'Hawaii': 4.44, 'Idaho': 6.03,
  'Illinois': 8.81, 'Indiana': 7.00, 'Iowa': 6.94, 'Kansas': 8.70,
  'Kentucky': 6.00, 'Louisiana': 9.55, 'Maine': 5.50, 'Maryland': 6.00,
  'Massachusetts': 6.25, 'Michigan': 6.00, 'Minnesota': 7.49, 'Mississippi': 7.07,
  'Missouri': 8.29, 'Montana': 0.0, 'Nebraska': 6.94, 'Nevada': 8.23,
  'New Hampshire': 0.0, 'New Jersey': 6.60, 'New Mexico': 7.72, 'New York': 8.52,
  'North Carolina': 6.98, 'North Dakota': 6.96, 'Ohio': 7.22, 'Oklahoma': 8.95,
  'Oregon': 0.0, 'Pennsylvania': 6.34, 'Rhode Island': 7.00, 'South Carolina': 7.46,
  'South Dakota': 6.40, 'Tennessee': 9.55, 'Texas': 8.19, 'Utah': 7.19,
  'Vermont': 6.24, 'Virginia': 5.75, 'Washington': 9.29, 'West Virginia': 6.50,
  'Wisconsin': 5.43, 'Wyoming': 5.33, 'Washington D.C.': 6.00,
};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializa Ads apenas se for Android ou iOS (Evita erro no Linux)
  if (Platform.isAndroid || Platform.isIOS) {
    MobileAds.instance.initialize();
  }
  
  // Orientação Retrato
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]).then((_) {
    runApp(const TaxApp());
  });
}

class TaxApp extends StatelessWidget {
  const TaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'US Tax Shopper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006400), // Verde Dólar
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF006400),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  
  // --- ESTADO GLOBAL ---
  List<Map<String, dynamic>> _history = [];
  double _budgetLimit = 0.0;
  String _selectedState = 'New York';
  
  // --- ADMOB ---
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  InterstitialAd? _interstitialAd;

 // --- CONFIGURAÇÃO DE ANÚNCIOS (RENDEY LLC) ---
  final String _bannerUnitId = Platform.isAndroid 
      ? 'ca-app-pub-3139983145335923/1560558248' // Seu ID Real de Banner
      : 'ca-app-pub-3139983145335923/1560558248';
      
  final String _interstitialUnitId = Platform.isAndroid
      ? 'ca-app-pub-3139983145335923/7934394903' // Seu ID Real de Intersticial
      : 'ca-app-pub-3139983145335923/7934394903';
      
  @override
  void initState() {
    super.initState();
    _loadData();
    // Só carrega anúncios se for Android/iOS
    if (Platform.isAndroid || Platform.isIOS) {
      _loadBannerAd();
      _createInterstitialAd();
    }
  }

  // --- AD LOGIC ---
  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: _bannerUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdReady = true),
        onAdFailedToLoad: (ad, err) { ad.dispose(); _isBannerAdReady = false; },
      ),
    )..load();
  }

  void _createInterstitialAd() {
    InterstitialAd.load(
        adUnitId: _interstitialUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (InterstitialAd ad) => _interstitialAd = ad,
          onAdFailedToLoad: (LoadAdError error) => _interstitialAd = null,
        ));
  }

  void _showInterstitial() {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _createInterstitialAd();
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          _createInterstitialAd();
        },
      );
      _interstitialAd!.show();
      _interstitialAd = null;
    }
  }

  // --- DATA LOGIC ---
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedState = prefs.getString('state') ?? 'New York';
      _budgetLimit = prefs.getDouble('budget') ?? 0.0;
      final historyString = prefs.getString('history');
      if (historyString != null) {
        _history = List<Map<String, dynamic>>.from(json.decode(historyString));
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('state', _selectedState);
    prefs.setDouble('budget', _budgetLimit);
    prefs.setString('history', json.encode(_history));
  }

  void _addItem(Map<String, dynamic> item) {
    setState(() {
      _history.insert(0, item);
      _saveData();
    });
    // Se a lista ficar grande, mostra anúncio (apenas mobile)
    if (_history.length % 5 == 0 && (Platform.isAndroid || Platform.isIOS)) {
      _showInterstitial();
    }
  }

  void _removeItem(int index) {
    setState(() {
      _history.removeAt(index);
      _saveData();
    });
  }

  void _clearHistory() {
    if (Platform.isAndroid || Platform.isIOS) _showInterstitial();
    setState(() {
      _history.clear();
      _saveData();
    });
  }

  void _updateBudget(double newBudget) {
    setState(() {
      _budgetLimit = newBudget;
      _saveData();
    });
  }

  void _updateState(String newState) {
    setState(() {
      _selectedState = newState;
      _saveData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      CalculatorTab(
        selectedState: _selectedState,
        budgetLimit: _budgetLimit,
        currentHistory: _history,
        onAddItem: _addItem,
        onStateChanged: _updateState,
      ),
      HistoryTab(
        history: _history,
        budgetLimit: _budgetLimit,
        onRemove: _removeItem,
        onClear: _clearHistory,
      ),
      SettingsTab(
        currentBudget: _budgetLimit,
        onUpdateBudget: _updateBudget,
      ),
    ];

    return Scaffold(
      body: SafeArea(child: screens[_currentIndex]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner Fixo (Só mostra se carregou)
          if (_isBannerAdReady)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
            indicatorColor: Colors.green.shade100,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.calculate_outlined),
                selectedIcon: Icon(Icons.calculate),
                label: 'Calc',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'My List',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Budget',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TELA 1: CALCULADORA (A Principal)
// ==========================================
class CalculatorTab extends StatefulWidget {
  final String selectedState;
  final double budgetLimit;
  final List<Map<String, dynamic>> currentHistory;
  final Function(Map<String, dynamic>) onAddItem;
  final Function(String) onStateChanged;

  const CalculatorTab({
    super.key,
    required this.selectedState,
    required this.budgetLimit,
    required this.currentHistory,
    required this.onAddItem,
    required this.onStateChanged,
  });

  @override
  State<CalculatorTab> createState() => _CalculatorTabState();
}

class _CalculatorTabState extends State<CalculatorTab> {
  final _priceCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  double _displayTotal = 0.0;
  double _displayTax = 0.0;
  bool _isReverse = false;

  @override
  void initState() {
    super.initState();
    _updateTaxRate();
  }

  @override
  void didUpdateWidget(CalculatorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedState != widget.selectedState) {
      _updateTaxRate();
    }
  }

  void _updateTaxRate() {
    if (widget.selectedState != 'Custom Rate') {
      _taxCtrl.text = usStatesTaxRates[widget.selectedState]!.toStringAsFixed(2);
    }
    _calculate();
  }

  void _calculate() {
    double price = double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
    double rate = double.tryParse(_taxCtrl.text.replaceAll(',', '.')) ?? 0.0;

    if (_isReverse) {
      double original = price / (1 + (rate / 100));
      setState(() {
        _displayTotal = price;
        _displayTax = price - original;
      });
    } else {
      double tax = price * (rate / 100);
      setState(() {
        _displayTax = tax;
        _displayTotal = price + tax;
      });
    }
  }

  void _saveItem() {
    if (_priceCtrl.text.isEmpty) return;
    HapticFeedback.mediumImpact();
    widget.onAddItem({
      'price': double.tryParse(_priceCtrl.text) ?? 0.0,
      'tax': _displayTax,
      'total': _displayTotal,
      'state': widget.selectedState,
      'isReverse': _isReverse,
      'date': DateTime.now().toIso8601String(),
    });
    _priceCtrl.clear();
    _calculate();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to your list!'), duration: Duration(milliseconds: 600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'en_US');
    
    // Budget
    double currentSpent = widget.currentHistory.fold(0.0, (sum, item) => sum + (item['total'] as double));
    double percent = widget.budgetLimit > 0 ? (currentSpent / widget.budgetLimit) : 0.0;
    if (percent > 1.0) percent = 1.0;
    Color statusColor = percent < 0.7 ? Colors.green : (percent < 0.95 ? Colors.orange : Colors.red);

    return Scaffold(
      appBar: AppBar(title: const Text('🇺🇸 Tax Calculator', style: TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // --- BUDGET BAR ---
            if (widget.budgetLimit > 0)
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, offset: const Offset(0, 2))],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Monthly Budget", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                        Text("${currency.format(currentSpent)} / ${currency.format(widget.budgetLimit)}", 
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearPercentIndicator(
                      lineHeight: 14.0,
                      percent: percent,
                      barRadius: const Radius.circular(10),
                      backgroundColor: Colors.grey[200],
                      progressColor: statusColor,
                      animation: true,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 15),

            // --- DISPLAY GRANDE ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  // AQUI ESTAVA O ERRO (uppercase: true). JÁ CORRIGIDO ABAIXO:
                  Text(
                    (_isReverse ? 'Sticker Price (Pre-Tax)' : 'You Pay (Post-Tax)').toUpperCase(), 
                    style: TextStyle(color: Colors.grey[600], fontSize: 12, letterSpacing: 1.2)
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    child: Text(
                      currency.format(_isReverse ? (_displayTotal - _displayTax) : _displayTotal),
                      style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: Color(0xFF006400)),
                    ),
                  ),
                  const Divider(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('TAX ADDED', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text(currency.format(_displayTax), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.redAccent)),
                      ]),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(20)),
                        child: Text(widget.selectedState, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      )
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- INPUTS ---
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: usStatesTaxRates.containsKey(widget.selectedState) ? widget.selectedState : 'New York',
                    decoration: InputDecoration(
                      labelText: 'State',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: usStatesTaxRates.keys.map((String state) {
                      return DropdownMenuItem<String>(
                        value: state,
                        child: Text(state, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) => widget.onStateChanged(val!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _taxCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: 'Tax %',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (_) => _calculate(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            
            TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: '\$ ',
                labelText: _isReverse ? 'Budget in hand' : 'Price tag',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
                suffixIcon: IconButton(
                  icon: Icon(_isReverse ? Icons.undo : Icons.swap_vert_circle, color: Colors.green),
                  tooltip: "Switch to Reverse Mode",
                  onPressed: () {
                    setState(() {
                      _isReverse = !_isReverse;
                      _calculate();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(_isReverse ? "Reverse Mode: Calculate price FROM total" : "Normal Mode: Calculate total FROM price"),
                      duration: const Duration(seconds: 1),
                    ));
                  },
                ),
              ),
              onChanged: (_) => _calculate(),
            ),
            const SizedBox(height: 20),
            
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _saveItem,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text("ADD TO LIST", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006400),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// TELA 2: HISTÓRICO (Lista de Compras)
// ==========================================
class HistoryTab extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final double budgetLimit;
  final Function(int) onRemove;
  final VoidCallback onClear;

  const HistoryTab({
    super.key,
    required this.history,
    required this.budgetLimit,
    required this.onRemove,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'en_US');
    double grandTotal = history.fold(0.0, (sum, item) => sum + (item['total'] as double));
    double totalTax = history.fold(0.0, (sum, item) => sum + (item['tax'] as double));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Shopping List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text("Clear List?"),
                content: const Text("This will remove all items."),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                  TextButton(onPressed: () {
                    Navigator.pop(ctx);
                    onClear();
                  }, child: const Text("Clear All", style: TextStyle(color: Colors.red))),
                ],
              ));
            },
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("TOTAL TAX", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(currency.format(totalTax), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text("GRAND TOTAL", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(currency.format(grandTotal), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black)),
                ]),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: history.isEmpty 
              ? Center(child: Text("Your cart is empty", style: TextStyle(color: Colors.grey[400], fontSize: 18)))
              : ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (ctx, i) {
                    final item = history[i];
                    return Dismissible(
                      key: Key(item['date'].toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (dir) => onRemove(i),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green[50],
                          child: const Icon(Icons.shopping_bag, color: Colors.green),
                        ),
                        title: Text(currency.format(item['total']), style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Price: ${currency.format(item['price'])} + Tax: ${currency.format(item['tax'])}"),
                        trailing: Text(item['state'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TELA 3: AJUSTES & BUDGET
// ==========================================
class SettingsTab extends StatefulWidget {
  final double currentBudget;
  final Function(double) onUpdateBudget;

  const SettingsTab({super.key, required this.currentBudget, required this.onUpdateBudget});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _budgetCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.currentBudget > 0) {
      _budgetCtrl.text = widget.currentBudget.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budget & Settings')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Set Monthly Budget", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text("Track your spending. The bar will turn red if you exceed this limit.", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 15),
            TextField(
              controller: _budgetCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: "\$ ",
                border: OutlineInputBorder(),
                labelText: "Limit Amount (Ex: 500)",
                helperText: "Set to 0 to disable",
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  double val = double.tryParse(_budgetCtrl.text) ?? 0.0;
                  widget.onUpdateBudget(val);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Budget Saved!")));
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006400), foregroundColor: Colors.white),
                child: const Text("SAVE BUDGET"),
              ),
            ),
            const SizedBox(height: 40),
            
            const Text("About", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text("Version 1.0.0"),
              subtitle: Text("US Sales Tax Calculator"),
            ),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text("Privacy Policy"),
              trailing: Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
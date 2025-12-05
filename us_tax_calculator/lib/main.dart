import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- DADOS: TAXAS MÉDIAS POR ESTADO (ESTIMATIVA 2025) ---
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
  'Custom Rate': 0.0,
};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  
  // Forçar modo retrato (App utilitário fica melhor em pé)
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
      .then((_) {
    runApp(const TaxApp());
  });
}

class TaxApp extends StatelessWidget {
  const TaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'US Tax Butler',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Verde Dólar para criar identidade visual
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006400)),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const CalculatorScreen(),
    );
  }
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  // --- CONTROLLADORES ---
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _taxRateController = TextEditingController();
  
  String _selectedState = 'New York'; // Padrão popular
  double _resultTotal = 0.0;
  double _resultTaxAmount = 0.0;
  bool _isReverseCalculation = false; // "Tenho $X, qual o preço da etiqueta?"
  
  // Lista de Compras (Retenção: Usuário usa enquanto faz compras)
  List<Map<String, dynamic>> _history = [];

  // --- ADMOB ---
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  InterstitialAd? _interstitialAd;
  int _actionCounter = 0; // Contar ações para exibir anúncio

  // IDs DE TESTE DO GOOGLE (Troque pelos seus reais na publicação)
  final String _bannerUnitId = Platform.isAndroid 
      ? 'ca-app-pub-3940256099942544/6300978111' 
      : 'ca-app-pub-3940256099942544/2934735716';
      
  final String _interstitialUnitId = Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-3940256099942544/4411468910';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _setTaxRateForState(_selectedState);
    _loadBannerAd();
    _createInterstitialAd();
  }

  // --- LÓGICA DE ANÚNCIOS ---
  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: _bannerUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdReady = true),
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          _isBannerAdReady = false;
        },
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

  void _showInterstitialAd() {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (Ad ad) {
          ad.dispose();
          _createInterstitialAd(); // Carrega o próximo
        },
        onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
          ad.dispose();
          _createInterstitialAd();
        },
      );
      _interstitialAd!.show();
      _interstitialAd = null;
    }
  }

  void _checkAdTrigger() {
    _actionCounter++;
    // Exibe anúncio tela cheia a cada 4 itens salvos (não irrita, mas monetiza)
    if (_actionCounter >= 4) {
      _showInterstitialAd();
      _actionCounter = 0;
    }
  }

  // --- CÁLCULOS ---
  void _setTaxRateForState(String state) {
    setState(() {
      _selectedState = state;
      if (state != 'Custom Rate') {
        _taxRateController.text = usStatesTaxRates[state]!.toStringAsFixed(2);
      }
      _calculate();
    });
  }

  void _calculate() {
    double price = double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0.0;
    double rate = double.tryParse(_taxRateController.text.replaceAll(',', '.')) ?? 0.0;

    if (_isReverseCalculation) {
      // Reverso: Total / (1 + taxa) = Preço Original
      double originalPrice = price / (1 + (rate / 100));
      setState(() {
        _resultTotal = price;
        _resultTaxAmount = price - originalPrice;
      });
    } else {
      // Normal: Preço * (1 + taxa) = Total
      double tax = price * (rate / 100);
      setState(() {
        _resultTaxAmount = tax;
        _resultTotal = price + tax;
      });
    }
  }

  // --- SALVAR DADOS (Retenção) ---
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyString = prefs.getString('history');
    if (historyString != null) {
      setState(() {
        _history = List<Map<String, dynamic>>.from(json.decode(historyString));
      });
    }
  }

  Future<void> _addToHistory() async {
    if (_priceController.text.isEmpty) return;
    FocusScope.of(context).unfocus(); // Esconder teclado

    final newItem = {
      'price': _priceController.text, // Valor digitado
      'state': _selectedState,
      'taxVal': _resultTaxAmount,
      'total': _resultTotal,
      'isReverse': _isReverseCalculation,
    };

    setState(() {
      _history.insert(0, newItem); // Adiciona no topo
    });
    
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('history', json.encode(_history));
    
    _priceController.clear();
    _calculate(); // Reseta display
    _checkAdTrigger(); // Checa se mostra anúncio
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to list!'), duration: Duration(milliseconds: 700)),
    );
  }

  Future<void> _clearHistory() async {
    setState(() => _history.clear());
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('history');
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.simpleCurrency(locale: 'en_US');

    return Scaffold(
      appBar: AppBar(
        title: const Text('🇺🇸 US Tax Butler', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF006400),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: _clearHistory,
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- CARD DE RESULTADO ---
                  Card(
                    elevation: 4,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Text(
                            _isReverseCalculation ? 'Original Price (Before Tax)' : 'Final Price (With Tax)',
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            currencyFormat.format(_isReverseCalculation ? (_resultTotal - _resultTaxAmount) : _resultTotal),
                            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF006400)),
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Tax Amount:', style: TextStyle(color: Colors.grey[600])),
                              Text(currencyFormat.format(_resultTaxAmount), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- CONTROLES ---
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedState,
                          decoration: const InputDecoration(
                            labelText: 'State',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                          ),
                          items: usStatesTaxRates.keys.map((String state) {
                            return DropdownMenuItem<String>(
                              value: state,
                              child: Text(state, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (val) => _setTaxRateForState(val!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _taxRateController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Tax %',
                            border: OutlineInputBorder(),
                            suffixText: '%',
                          ),
                          onChanged: (_) => _calculate(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  
                  TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 22),
                    decoration: InputDecoration(
                      labelText: _isReverseCalculation ? 'I have this total amount:' : 'Price on sticker:',
                      prefixText: '\$ ',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_isReverseCalculation ? Icons.undo : Icons.autorenew),
                        onPressed: () {
                          setState(() {
                            _isReverseCalculation = !_isReverseCalculation;
                            _calculate();
                          });
                        },
                      ),
                    ),
                    onChanged: (_) => _calculate(),
                  ),
                  const SizedBox(height: 15),

                  ElevatedButton.icon(
                    onPressed: _addToHistory,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('ADD TO LIST', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF006400),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),

                  const SizedBox(height: 25),
                  const Text("Shopping History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  // --- LISTA DE HISTÓRICO ---
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      return ListTile(
                        leading: const Icon(Icons.receipt_long, color: Colors.grey),
                        title: Text(currencyFormat.format(item['total'])),
                        subtitle: Text("${item['state']} Tax: ${currencyFormat.format(item['taxVal'])}"),
                        trailing: Text(item['isReverse'] ? 'Reverse' : 'Regular', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // --- BANNER AD NO RODAPÉ ---
          if (_isBannerAdReady)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }
}
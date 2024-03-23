import 'dart:ffi';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:mqtt_client/mqtt_server_client.dart' as mqtt;

import 'environment_list.dart';
import 'settings_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter MQTT Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Household Environment'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {

  late mqtt.MqttServerClient client;
  bool irblasterQueryInFlight = false;
  String currentDeltaDegrees = '--';
  List<TemperatureItem> items = [];
  late dynamic rootConfig;

  Timer? _timer; // Timer reference

  @override
  void initState() {
    super.initState();

    const period = Duration(seconds: 30); // Adjust the period as needed
    _timer = Timer.periodic(period, (timer) {
      fetchDelta();
    });
    fetchDelta();

    doAsyncLoading();

    WidgetsBinding.instance.addObserver(this);
  }

  void doAsyncLoading() async {
    // load config from JSON file
    final configJson = await rootBundle.loadString("assets/config.json");
    rootConfig = await json.decode(configJson);

    rootConfig['environment_entries'].forEach((entry) {
      items.add(
        TemperatureItem(
          id: entry['id'],
          label: entry['label'],
          temperature_topic: entry['temperature_topic'],
          humidity_topic: entry['humidity_topic']
        )
      );
    });

    setState(() {
      items = items;
    });

    _connectToMqtt();
  }

  void fetchDelta() async {
    // try {
      final since = (DateTime.now().millisecondsSinceEpoch / 1000) - (1 * 60 * 60);
      var url = Uri.parse('http://192.168.1.2:8003/time-series?topic=xiaomi_mijia/M_GARAGE/temperature&topic=xiaomi_mijia/M_BKROOM/temperature&chunk=3600&since=$since');
      var response = await http.get(url);

      if (response.statusCode == 200) {

        // If the server returns a 200 OK response, parse the JSON
        Map<String, dynamic> jsonResponse = json.decode(response.body);

        if (jsonResponse.containsKey('xiaomi_mijia/M_GARAGE/temperature') && jsonResponse.containsKey('xiaomi_mijia/M_BKROOM/temperature') && jsonResponse['xiaomi_mijia/M_GARAGE/temperature'] is List && jsonResponse['xiaomi_mijia/M_BKROOM/temperature'] is List) {
          // Cast jsonResponse[topic] to List and then map to List<FlSpot>
          final garageTempList = List.from(jsonResponse['xiaomi_mijia/M_GARAGE/temperature']);
          final officeTempList = List.from(jsonResponse['xiaomi_mijia/M_BKROOM/temperature']);

          if (!(garageTempList is List) || !(officeTempList is List) || garageTempList.length < 1 || officeTempList.length < 1) {
            setState(() {
              currentDeltaDegrees = 'error';
            });
            return;
          }

          final garageTemp = (garageTempList[0][1] * (9/5.0)) + 32;
          final officeTemp = (officeTempList[0][1] * (9/5.0)) + 32;

          setState(() {
            currentDeltaDegrees = '${(officeTemp - garageTemp).toStringAsFixed(1)}°F';
          });
        }

      } else {
        // If the server did not return a 200 OK response,
        // throw an exception.
        setState(() {
          currentDeltaDegrees = 'error ${response.statusCode.toString()}';
        });
        throw Exception('Failed to load data');
      }
    // } catch (e) {
    //   // Handle any exceptions here
    //   setState(() {
    //     currentDeltaDegrees = 'error ${e.toString()}';
    //   });
    // }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _saveItems(items);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('AppLifecycleState changed: $state');
    // if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
    //   _saveItems(items);
    // }
  }

  void _saveItems(List<TemperatureItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    // Convert each item to a JSON map and then to a string
    // don't store items members that have hasBeenUpdated == false
    List<String> stringList = items.where((item) => item.hasBeenUpdated).map((item) => json.encode(item.toJson())).toList();
    print('Saving items: $stringList');
    await prefs.setStringList('temperature_items', stringList);
  }

  Future<List<TemperatureItem>> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> stringList = prefs.getStringList('temperature_items') ?? [];
    // Convert each string back to a TemperatureItem
    return stringList.map((itemStr) => TemperatureItem.fromJson(json.decode(itemStr))).toList();
  }

  void _connectToMqtt() async {
    client = mqtt.MqttServerClient(rootConfig['host'].toString(), rootConfig['client_id'].toString());
    client.onConnected = _onConnected;
    client.onSubscribed = _onSubscribed;
    client.onDisconnected = _onDisconnected;
    client.onUnsubscribed = _onUnsubscribed;

    try {
      await client.connect();
    } catch (e) {
      print('Exception: $e');
      client.disconnect();
    }
  }

  void _onConnected() {
    print('Connected to MQTT');
    for (var entry in rootConfig['subscribe']) {
      client.subscribe(entry.toString(), mqtt.MqttQos.atMostOnce);
    }
  }

  void _onDisconnected() {
    print('Disconnected from MQTT');
  }

  void _onSubscribed(String topic) {
    print('Subscribed to topic: $topic');

    client.updates!.listen((List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> messageList) {
      for(var entry in messageList) {
        final String topic = entry.topic;
        final recMsg = entry.payload as mqtt.MqttPublishMessage;
        String message = mqtt.MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);

        // iterate through items and find the one that matches the topic
        for(var i = 0; i < items.length; i++) {
          if (items[i].temperature_topic == topic) {
            setState(() {
              items[i].temperature = "${((double.tryParse(message)! * 1.8) + 32).toStringAsFixed(1)} ºF";
              items[i].hasBeenUpdated = true;
            });
          }
          else if (items[i].humidity_topic == topic) {
            setState(() {
              items[i].humidity = "${(double.tryParse(message)!).toStringAsFixed(1)} %";
              items[i].hasBeenUpdated = true;
            });
          }
        }
      }
    });
  }

  void _onUnsubscribed(String? topic) {
    print('Unsubscribed from topic: $topic');
  }

  void toggleLoading() async {
    setState(() {
      irblasterQueryInFlight = true; // Show loading indicator
    });

    var url = Uri.parse('http://192.168.45.4:80/msg?code=10AF8877:NEC:32&address=0xf508&pass=XHV2HFCTyi&simple=1');
    var response = await http.get(url);

    setState(() {
      irblasterQueryInFlight = false; // Hide loading indicator
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.settings), // Gear icon for settings
            onPressed: () {
              // Navigate to the settings page
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsPage()),
              );
            },
          ),
        ]
      ),
      body: Column(
        children: [
          Expanded(flex:4, child: EnvironmentListView(items: items)),
          Expanded(flex:1, child: Row(
            children: [
              Expanded(
                child: Center(child: Text('Garage/Office Δ\n' + currentDeltaDegrees, textAlign: TextAlign.center,)),
              ),
              Expanded(
                child: Center(
                  child: irblasterQueryInFlight
                      ? CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: toggleLoading,
                          child: Text('A/C Power Toggle'),
                        ),
                ),
              )
            ],
          ))
        ]
      )
    );
  }
}

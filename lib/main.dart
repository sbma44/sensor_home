import 'dart:ffi';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:mqtt_client/mqtt_server_client.dart' as mqtt;
import 'package:uuid/uuid.dart';

import 'environment_list.dart';
import 'settings_page.dart';
import 'detail.dart';

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
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  mqtt.MqttServerClient? client;
  bool irblasterQueryInFlight = false;
  String currentDeltaDegrees = '--';
  String title = '';
  String toggleButtonText = 'Toggle';
  List<TemperatureItem> items = [];
  late dynamic rootConfig;
  late String userid;
  bool isInSelectionMode = false;

  Timer? _timer; // Timer reference

  @override
  void initState() {
    super.initState();

    doAsyncLoading();

    WidgetsBinding.instance.addObserver(this);
  }

  void doAsyncLoading() async {
    void processRetrievedConfig() {
      // load config from JSON file
      rootConfig['environment_entries'].forEach((entry) {
        // find item with matching id and update its field values or, if none exists, add a new one
        var found = false;
        for (var i = 0; i < items.length; i++) {
          if (items[i].id == entry['id']) {
            items[i].label = entry['label'];
            items[i].temperature_topic = entry['temperature_topic'];
            items[i].humidity_topic = entry['humidity_topic'];
            found = true;
            break;
          }
        }
        if (!found) {
          items.add(TemperatureItem(
              id: entry['id'],
              label: entry['label'],
              temperature_topic: entry['temperature_topic'],
              humidity_topic: entry['humidity_topic']));
        }
      });

      setState(() {
        items = items;
      });

      if (rootConfig['title'] != null) {
        setState(() {
          title = rootConfig['title'];
        });
      }

      if (rootConfig['button'] != null) {
        setState(() {
          toggleButtonText = rootConfig['button'][0].toString();
        });
      }

      _connectToMqtt();

      const period = Duration(seconds: 30); // Adjust the period as needed
      _timer = Timer.periodic(period, (timer) {
        fetchDelta();
      });
      fetchDelta();
    }

    Future<bool> fetchConfigFromServer() async {
      final configJson = await rootBundle.loadString("assets/config.json");
      var conf = await json.decode(configJson);

      final prefs = await SharedPreferences.getInstance();
      var url = Uri.parse('${conf["config"]}?u=${userid}');
      var response = await http.get(url);
      if (response.statusCode == 200) {
        await prefs.setString('configJson', response.body);
        rootConfig = await json.decode(response.body);
        processRetrievedConfig();
        return true;
      } else {
        return false;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    userid = prefs.getString('userid') ?? '';
    if (userid == '') {
      const uuid = Uuid();
      userid = uuid.v4();
      await prefs.setString('userid', userid);
    }

    // load config from prefs, if available. if not, fetch from server
    var configJsonString = prefs.getString('configJson') ?? '';
    if (configJsonString == '') {
      var success = await fetchConfigFromServer();
      if (!success) {
        // indicate error condition somehow
      }
    } else {
      rootConfig = await json.decode(configJsonString);
      processRetrievedConfig();

      fetchConfigFromServer(); // refresh config, but don't wait for it
    }
  }

  void fetchDelta() async {
    final since =
        (DateTime.now().millisecondsSinceEpoch / 1000) - (1 * 60 * 60);
    final topic1 = rootConfig['delta']['topic1'].toString();
    final topic2 = rootConfig['delta']['topic2'].toString();
    final chunk = rootConfig['delta']['chunk'].toString();
    var url = Uri.parse(rootConfig['delta']['url']
        .toString()
        .replaceAll('{topic1}', topic1)
        .replaceAll('{topic2}', topic2)
        .replaceAll('{chunk}', chunk)
        .replaceAll('{since}', since.toString()));
    var response = await http.get(url);

    if (response.statusCode == 200) {
      // If the server returns a 200 OK response, parse the JSON
      Map<String, dynamic> jsonResponse = json.decode(response.body);

      if (jsonResponse.containsKey(topic1) &&
          jsonResponse.containsKey(topic2) &&
          jsonResponse[topic1] is List &&
          jsonResponse[topic2] is List) {
        // Cast jsonResponse[topic] to List and then map to List<FlSpot>
        final garageTempList = List.from(jsonResponse[topic1]);
        final officeTempList = List.from(jsonResponse[topic2]);

        if (garageTempList.isEmpty || officeTempList.isEmpty) {
          setState(() {
            currentDeltaDegrees = 'error';
          });
          return;
        }

        final garageTemp = (garageTempList[0][1] * (9 / 5.0)) + 32;
        final officeTemp = (officeTempList[0][1] * (9 / 5.0)) + 32;

        setState(() {
          currentDeltaDegrees =
              '${(officeTemp - garageTemp).toStringAsFixed(1)}°F';
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('AppLifecycleState changed: $state');
  }

  void _connectToMqtt() async {
    // reconnect if invoked and the server has changed. otherwise return silently
    if (client?.connectionStatus!.state == mqtt.MqttConnectionState.connected) {
      if (client?.server == rootConfig['mqtt_host'].toString() &&
          client?.clientIdentifier == rootConfig['client_id'].toString()) {
        return;
      }
      client!.disconnect();
    }
    client = mqtt.MqttServerClient(
        rootConfig['mqtt_host'].toString(), rootConfig['client_id'].toString());
    client!.onConnected = _onConnected;
    client!.onSubscribed = _onSubscribed;
    client!.onDisconnected = _onDisconnected;
    client!.onUnsubscribed = _onUnsubscribed;

    try {
      await client!.connect();
    } catch (e) {
      print('Exception: $e');
      client!.disconnect();
    }
  }

  void _onConnected() {
    print('Connected to MQTT');
    for (var entry in rootConfig['subscribe']) {
      client!.subscribe(entry.toString(), mqtt.MqttQos.atMostOnce);
    }
  }

  void _onDisconnected() {
    print('Disconnected from MQTT');
  }

  void _onSubscribed(String topic) {
    print('Subscribed to topic: $topic');

    client!.updates!
        .listen((List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> messageList) {
      for (var entry in messageList) {
        final String topic = entry.topic;
        final recMsg = entry.payload as mqtt.MqttPublishMessage;
        String message = mqtt.MqttPublishPayload.bytesToStringAsString(
            recMsg.payload.message);

        // iterate through items and find the one that matches the topic
        for (var i = 0; i < items.length; i++) {
          if (items[i].temperature_topic == topic) {
            setState(() {
              items[i].temperature =
                  "${((double.tryParse(message)! * 1.8) + 32).toStringAsFixed(1)} ºF";
              items[i].hasBeenUpdated = true;
            });
          } else if (items[i].humidity_topic == topic) {
            setState(() {
              items[i].humidity =
                  "${(double.tryParse(message)!).toStringAsFixed(1)} %";
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

    var url = Uri.parse(rootConfig['button'][1].toString());
    var response = await http.get(url);

    setState(() {
      irblasterQueryInFlight = false; // Hide loading indicator
    });
  }

  void onTapCallback(int index) {
    if (!isInSelectionMode) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              DetailScreen(config: rootConfig, items: [items[index]]),
        ),
      );
    } else {
      setState(() {
        items[index].isSelected = !items[index].isSelected;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: Text(title),
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
            ]),
        body: Column(children: [
          Expanded(
              flex: 8,
              child: EnvironmentListView(
                  items: items, onTapCallback: onTapCallback)),
          Expanded(
              flex: 1,
              child: Text(
                'Garage/Office Δ ' + currentDeltaDegrees,
                textAlign: TextAlign.center,
              )),
          Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: ElevatedButton(
                          onPressed: () {
                            // note whether we're going to be navigating to the detail screen
                            var selectedItems =
                                items.where((el) => el.isSelected).toList();
                            bool navigateToDetailScreen =
                                (selectedItems.length >= 2) &&
                                    isInSelectionMode;

                            // toggle selection mode. if we're leaving it, deselect everything
                            setState(() {
                              isInSelectionMode = !isInSelectionMode;
                              if (!isInSelectionMode) {
                                for (var i = 0; i < items.length; i++) {
                                  items[i].isSelected = false;
                                }
                              }
                            });

                            if (navigateToDetailScreen) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DetailScreen(
                                      config: rootConfig, items: selectedItems),
                                ),
                              );
                            }
                          },
                          style: ButtonStyle(
                            backgroundColor:
                                MaterialStateProperty.resolveWith<Color?>(
                              (Set<MaterialState> states) {
                                if (isInSelectionMode) {
                                  return Theme.of(context)
                                      .colorScheme
                                      .inversePrimary;
                                }
                                return null;
                              },
                            ),
                          ),
                          child:
                              (items.where((el) => el.isSelected).length >= 2)
                                  ? const Text('Compare')
                                  : const Text('Select')),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: irblasterQueryInFlight
                          ? CircularProgressIndicator()
                          : ElevatedButton(
                              onPressed: toggleLoading,
                              child: Text(toggleButtonText),
                            ),
                    ),
                  )
                ],
              ))
        ]));
  }
}

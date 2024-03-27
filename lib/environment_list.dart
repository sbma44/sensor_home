import 'package:flutter/material.dart';
import 'detail.dart';

class TemperatureItem {
  String id;
  String label;
  String temperature_topic;
  String humidity_topic;
  String temperature;
  String humidity;
  bool hasBeenUpdated;
  bool isSelected = false;

  TemperatureItem({required this.id, required this.label, required this.temperature_topic, required this.humidity_topic, this.temperature = '', this.humidity = '', this.hasBeenUpdated = false});

  // Convert a TemperatureItem object to a Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'temperature_topic': temperature_topic,
      'humidity_topic': humidity_topic,
      'temperature': temperature,
      'humidity': humidity,
    };
  }

  // Create a TemperatureItem object from a Map
  factory TemperatureItem.fromJson(Map<String, dynamic> json) {
    return TemperatureItem(
      id: json['id'],
      label: json['label'],
      temperature_topic: json['temperature_topic'],
      humidity_topic: json['humidity_topic'],
      temperature: json['temperature'],
      humidity: json['humidity'],
      hasBeenUpdated: false
    );
  }
}

class EnvironmentListView extends StatelessWidget {
  final List<TemperatureItem> items;
  final Function onTapCallback;

  const EnvironmentListView({Key? key, required this.items, required this.onTapCallback}) : super(key: key);

  TextStyle rowTextStyle(bool hasBeenUpdated, bool isSelected) {
    return hasBeenUpdated ? TextStyle() : TextStyle(
      color: Colors.grey[400]
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
        itemCount: items.length,
        itemBuilder: (context, index) {
          return Container(
            child: ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  // Label on the left
                  Text(items[index].label, style: rowTextStyle(items[index].hasBeenUpdated, items[index].isSelected)),

                  // Temperature and Humidity on the right
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(items[index].temperature, style: rowTextStyle(items[index].hasBeenUpdated, items[index].isSelected)),
                      Text(items[index].humidity, style: rowTextStyle(items[index].hasBeenUpdated, items[index].isSelected)),
                    ],
                  ),
                ],
              ),
              onTap: () {
                onTapCallback(index);
              },
              tileColor: items[index].isSelected ? Theme.of(context).colorScheme.inversePrimary : Colors.white,
            ),
          );
        },
        separatorBuilder: (context, index) {
          return Divider(
            color: Colors.grey[300], // Change the color as needed
            height: 1,  // Can adjust the height for spacing
          );
        }
      );
  }
}

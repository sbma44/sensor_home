import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For JSON parsing
import 'package:fl_chart/fl_chart.dart';

class AppColors {
  static const Color primary = contentColorCyan;
  static const Color menuBackground = Color(0xFF090912);
  static const Color itemsBackground = Color(0xFF1B2339);
  static const Color pageBackground = Color(0xFF282E45);
  static const Color mainTextColor1 = Colors.white;
  static const Color mainTextColor2 = Colors.white70;
  static const Color mainTextColor3 = Colors.white38;
  static const Color mainGridLineColor = Colors.white10;
  static const Color borderColor = Colors.white54;
  static const Color gridLinesColor = Color(0x11FFFFFF);

  static const Color contentColorBlack = Colors.black;
  static const Color contentColorWhite = Colors.white;
  static const Color contentColorBlue = Color(0xFF2196F3);
  static const Color contentColorYellow = Color(0xFFFFC300);
  static const Color contentColorOrange = Color(0xFFFF683B);
  static const Color contentColorGreen = Color(0xFF3BFF49);
  static const Color contentColorPurple = Color(0xFF6E1BFF);
  static const Color contentColorPink = Color(0xFFFF3AF2);
  static const Color contentColorRed = Color(0xFFE80054);
  static const Color contentColorCyan = Color(0xFF50E4FF);
}

class MyTimeSeriesChart extends StatelessWidget {
  final List<FlSpot> dataPoints;

  MyTimeSeriesChart({required this.dataPoints});

  String formatUnixTimestamp(int timestamp) {
    DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    String formattedTime = DateFormat('h:mma').format(dateTime).toLowerCase();
    return formattedTime;
  }

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 16,
    );
    DateTime dateTime = DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
    return (dateTime.minute != 0) ? Container() : SideTitleWidget(
      axisSide: meta.axisSide,
      space: 10,
      child: Text(DateFormat('h:mma').format(dateTime).toLowerCase(), style: style)
    );
  }

  List<Color> gradientColors = [
    AppColors.contentColorCyan,
    AppColors.contentColorBlue,
  ];

  @override
  Widget build(BuildContext context) {
    return dataPoints.length <= 1 ? Container() : LineChart(
      LineChartData(
        minX: dataPoints[0].x,
        maxX: dataPoints[dataPoints.length - 1].x,
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: 360,
          verticalInterval: 10,
          getDrawingHorizontalLine: (value) {
            return const FlLine(
              color: AppColors.mainGridLineColor,
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return const FlLine(
              color: AppColors.mainGridLineColor,
              strokeWidth: 1,
            );
          },
        ),
        lineBarsData: [
          LineChartBarData(
            spots: dataPoints,
            isCurved: true,
            gradient: LinearGradient(
              colors: gradientColors,
            ),
            barWidth: 5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: gradientColors
                    .map((color) => color.withOpacity(0.3))
                    .toList(),
              ),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 60 * 60 * 6,
              getTitlesWidget: bottomTitleWidgets,
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
      ),
    );
  }
}

class DetailScreen extends StatefulWidget {
  final String topic;
  final String label;

  const DetailScreen({super.key, required this.topic, required this.label});

  @override
  _DetailScreenState createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late List<FlSpot> dataPoints = []; // This will hold the data for the chart
  bool isLoading = true;
  bool isError = false;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  void fetchData() async {
    try {
      final since = (DateTime.now().millisecondsSinceEpoch / 1000) - (24 * 60 * 60);
      var url = Uri.parse('http://192.168.1.2:8003/time-series?topic=${widget.topic}&chunk=300&since=$since');
      var response = await http.get(url);

      if (response.statusCode == 200) {

        // If the server returns a 200 OK response, parse the JSON
        Map<String, dynamic> jsonResponse = json.decode(response.body);

        if (jsonResponse.containsKey(widget.topic) && jsonResponse[widget.topic] is List) {
          // Cast jsonResponse[topic] to List and then map to List<FlSpot>
          List<FlSpot> loadedDataPoints = List.from(jsonResponse[widget.topic]).map((data) {
            // Ensure 'data' has at least two elements
            if (data is List && data.length >= 2) {
              return FlSpot(data[0].toDouble(), double.parse(((data[1].toDouble() * 9 / 5.0) + 32.0).toStringAsFixed(1)));
            }
            else {
              print(data);
            }
            return FlSpot(0, 0); // Return a default value or handle this case as needed
          }).toList();

          setState(() {
            dataPoints = loadedDataPoints;
            isLoading = false;
          });
        }

      } else {
        // If the server did not return a 200 OK response,
        // throw an exception.
        setState(() {
          isError = true;
        });
        throw Exception('Failed to load data');
      }
    } catch (e) {
      // Handle any exceptions here
      setState(() {
        isError = true;
      });
      print('Error fetching data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label),
      ),
      body: Column(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
            child: isError ? const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 60,
              ) :
            isLoading ? Center(child: const CircularProgressIndicator()) : MyTimeSeriesChart(dataPoints: dataPoints)
          )
        ),
      ],)
    );
  }
}

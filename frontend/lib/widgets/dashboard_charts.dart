import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';

class ProjectTrendChart extends ConsumerStatefulWidget {
  const ProjectTrendChart({super.key});

  @override
  ConsumerState<ProjectTrendChart> createState() => _ProjectTrendChartState();
}

class _ProjectTrendChartState extends ConsumerState<ProjectTrendChart> {
  List<Color> gradientColors = [
    Colors.purple.shade300,
    Colors.purple.shade600,
  ];

  @override
  Widget build(BuildContext context) {
    final chartDataAsync = ref.watch(dashboardChartDataProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'New Projects',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last 6 months',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Trend',
                  style: TextStyle(
                    color: Colors.purple.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          AspectRatio(
            aspectRatio: 1.70,
            child: chartDataAsync.when(
              data: (data) {
                final trendData = data['projectTrend'] as List<dynamic>;
                if (trendData.isEmpty) {
                  return const Center(child: Text("No data available"));
                }
                return LineChart(mainData(trendData));
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  LineChartData mainData(List<dynamic> trendData) {
    // Generate spots
    List<FlSpot> spots = [];
    double maxY = 0;
    
    for (int i = 0; i < trendData.length; i++) {
      final count = (trendData[i]['count'] as num).toDouble();
      if (count > maxY) maxY = count;
      spots.add(FlSpot(i.toDouble(), count));
    }
    
    // Add some buffer to maxY
    maxY = (maxY == 0) ? 5 : maxY * 1.2;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 1,
        verticalInterval: 1,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey.withOpacity(0.1),
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: (value, meta) {
               int index = value.toInt();
               if (index >= 0 && index < trendData.length) {
                 return SideTitleWidget(
                   axisSide: meta.axisSide,
                   child: Text(
                     trendData[index]['month'].toString(),
                     style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                   ),
                 );
               }
               return Container();
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1, // Auto-scale interval? Let's keep it simple or calc
            getTitlesWidget: (value, meta) {
              if (value % 1 == 0) {
                 return Text(
                    value.toInt().toString(), 
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey,
                    ), 
                    textAlign: TextAlign.left
                  );
              }
              return Container();
            },
            reservedSize: 28,
          ),
        ),
      ),
      borderData: FlBorderData(
        show: false,
      ),
      minX: 0,
      maxX: (trendData.length - 1).toDouble(),
      minY: 0,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          gradient: LinearGradient(
            colors: gradientColors,
          ),
          barWidth: 5,
          isStrokeCapRound: true,
          dotData: const FlDotData(
            show: true, // Show dots for clearer data points
          ),
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
    );
  }
}

class DomainDistributionChart extends ConsumerStatefulWidget {
  const DomainDistributionChart({super.key});

  @override
  ConsumerState<DomainDistributionChart> createState() =>
      _DomainDistributionChartState();
}

class _DomainDistributionChartState extends ConsumerState<DomainDistributionChart> {
  int touchedIndex = -1;

  // Colors for domains
  final List<Color> _domainColors = [
    const Color(0xFF5D3AC0),
    const Color(0xFF8B5CF6),
    const Color(0xFFA78BFA),
    const Color(0xFFC4B5FD),
    Colors.purple.shade900,
    Colors.deepPurple.shade300,
  ];

  @override
  Widget build(BuildContext context) {
    final chartDataAsync = ref.watch(dashboardChartDataProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Domains',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Active projects',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz))
            ],
          ),
          const SizedBox(height: 32),
          chartDataAsync.when(
            data: (data) {
              final domainMap = data['domainDistribution'] as Map<String, int>;
              if (domainMap.isEmpty) {
                 return const SizedBox(
                   height: 200, 
                   child: Center(child: Text("No domain data"))
                 );
              }
              
              final sortedEntries = domainMap.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              
              // Only take top 4-5 and group others if needed, but for now simple
              
              return AspectRatio(
                aspectRatio: 1.3,
                child: Row(
                  children: [
                    const SizedBox(height: 18),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: PieChart(
                          PieChartData(
                            pieTouchData: PieTouchData(
                              touchCallback:
                                  (FlTouchEvent event, pieTouchResponse) {
                                setState(() {
                                  if (!event.isInterestedForInteractions ||
                                      pieTouchResponse == null ||
                                      pieTouchResponse.touchedSection == null) {
                                    touchedIndex = -1;
                                    return;
                                  }
                                  touchedIndex = pieTouchResponse
                                      .touchedSection!.touchedSectionIndex;
                                });
                              },
                            ),
                            borderData: FlBorderData(
                              show: false,
                            ),
                            sectionsSpace: 0,
                            centerSpaceRadius: 40,
                            sections: showingSections(sortedEntries),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 28),
                    // Legend
                    Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(sortedEntries.length, (index) {
                         if (index >= _domainColors.length) return const SizedBox.shrink();
                         return Padding(
                           padding: const EdgeInsets.only(bottom: 4.0),
                           child: Indicator(
                             color: _domainColors[index],
                             text: sortedEntries[index].key,
                             isSquare: true,
                           ),
                         );
                      }),
                    ),
                    const SizedBox(width: 28),
                  ],
                ),
              );
            },
            loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
            error: (err, _) => SizedBox(height: 200, child: Center(child: Text('Error: $err'))),
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> showingSections(List<MapEntry<String, int>> dataEntries) {
    int total = dataEntries.fold(0, (sum, item) => sum + item.value);
    
    return List.generate(dataEntries.length, (i) {
      if (i >= _domainColors.length) return null; // Limit segments
      
      final isTouched = i == touchedIndex;
      final fontSize = isTouched ? 20.0 : 14.0;
      final radius = isTouched ? 60.0 : 50.0;
      final value = dataEntries[i].value;
      final percentage = (value / total * 100).toStringAsFixed(0);
      
      return PieChartSectionData(
        color: _domainColors[i],
        value: value.toDouble(),
        title: '$percentage%',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black26, blurRadius: 2)],
        ),
      );
    }).whereType<PieChartSectionData>().toList();
  }
}

class Indicator extends StatelessWidget {
  const Indicator({
    super.key,
    required this.color,
    required this.text,
    required this.isSquare,
    this.size = 16,
    this.textColor,
  });
  final Color color;
  final String text;
  final bool isSquare;
  final double size;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
            color: color,
            borderRadius: isSquare ? BorderRadius.circular(4) : null,
          ),
        ),
        const SizedBox(
          width: 4,
        ),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: textColor ?? Colors.grey.shade700,
          ),
        )
      ],
    );
  }
}


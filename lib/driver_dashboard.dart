import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

enum PathfindingAlgorithm {
  floydWarshall,
  dStar
}

class DriverDashboard extends StatefulWidget {
  final String userId;

  const DriverDashboard({super.key, required this.userId});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  List<Map<String, dynamic>> _nearbyOrders = [];
  Position? _currentPosition;
  final MapController _mapController = MapController();
  bool _isLoading = true;
  String? _errorMessage;
  List<LatLng> currentRoute = [];
  int routeVersion = 0;
  double currentRouteDistance = 0;
  bool _showSatellite = false;
  PathfindingAlgorithm currentAlgorithm = PathfindingAlgorithm.floydWarshall;
  final String mapboxUsername = 'naveen1907';
  final String mapboxStyleId = 'cm7qln389003g01sc1z1be4ih';
  final String mapboxAccessToken = 'pk.eyJ1IjoibmF2ZWVuMTkwNyIsImEiOiJjbTdxNW0zaGEwcG1uMnFyMTBuNmwzNWcwIn0.ehEnrtYOzwMU6-YnM15seg';
  bool _showMap = true;
  double _fuelSaved = 0.0;
  int _estimatedTimeReduction = 0;
  int _deliveriesCompleted = 0;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      await _getCurrentLocation();
      await _fetchAssignedOrders();
      
    } catch (e) {
      print('Error in _initializeData: $e');
      setState(() {
        _errorMessage = 'Failed to initialize: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      print('Current position obtained: $position');

      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      print('Error getting location: $e');
      // For testing, set a default position in Vizag
      setState(() {
        _currentPosition = Position(
          latitude: 17.7231,
          longitude: 83.3013,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      });
    }
  }

  Future<void> _fetchAssignedOrders() async {
    try {
      print('Fetching assigned orders for driver: ${widget.userId}');
      
      final response = await Supabase.instance.client
          .from('orders')
          .select()
          .eq('status', 'pending')
          .eq('driver_id', widget.userId);

      print('Orders response: $response');

      final List<Map<String, dynamic>> orders = List<Map<String, dynamic>>.from(response as List);
      print('Assigned orders found: ${orders.length}');

      setState(() {
        _nearbyOrders = orders;
        _isLoading = false;
        if (orders.isNotEmpty) {
          _calculateOptimalRoute();
        }
      });
    } catch (e) {
      print('Error in _fetchAssignedOrders: $e');
      setState(() {
        _errorMessage = 'Failed to fetch orders: $e';
        _isLoading = false;
      });
    }
  }

  void _calculateOptimalRoute() {
    if (_nearbyOrders.isEmpty || _currentPosition == null) {
      print('Cannot calculate route: orders empty or no current position');
      return;
    }

    try {
      // Create list of points starting with current position
      List<LatLng> points = [
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      ];

      // Add delivery points from orders
      for (var order in _nearbyOrders) {
        if (order['delivery_latitude'] != null && order['delivery_longitude'] != null) {
          points.add(LatLng(
            double.parse(order['delivery_latitude'].toString()),
            double.parse(order['delivery_longitude'].toString()),
          ));
        }
      }

      print('Calculating route with ${points.length} points:');
      points.forEach((point) => print('Point: ${point.latitude}, ${point.longitude}'));

      setState(() {
        routeVersion++;
        switch (currentAlgorithm) {
          case PathfindingAlgorithm.floydWarshall:
            currentRoute = findPathFloydWarshall(points);
            print('Floyd-Warshall route calculated with ${currentRoute.length} points');
          case PathfindingAlgorithm.dStar:
            currentRoute = findPathDStar(points);
            print('D* route calculated with ${currentRoute.length} points');
        }
        _calculateRouteDistance();
        print('Route distance: ${currentRouteDistance.toStringAsFixed(2)} meters');

        // Update efficiency metrics
        _fuelSaved = currentRouteDistance * 0.15; // Estimated fuel savings (L)
        _estimatedTimeReduction = (currentRouteDistance / 500).round(); // Rough estimate of time saved

        // Center map on the route
        if (currentRoute.isNotEmpty) {
          _mapController.fitBounds(
            LatLngBounds.fromPoints(currentRoute),
            options: const FitBoundsOptions(padding: EdgeInsets.all(50.0)),
          );
        }

        // Show optimization results
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Route optimized! Estimated savings: '
                '${_estimatedTimeReduction}min, '
                '${_fuelSaved.toStringAsFixed(1)}L fuel'
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      });
    } catch (e) {
      print('Error in route calculation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to calculate route: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<LatLng> findPathFloydWarshall(List<LatLng> points) {
    if (points.isEmpty || points.length <= 2) return List.from(points);

    final int n = points.length;
    final distance = Distance();
    
    // Initialize distance matrix
    List<List<double>> dist = List.generate(
      n,
      (i) => List.generate(
        n,
        (j) => i == j ? 0 : distance.as(LengthUnit.Meter, points[i], points[j])
      )
    );

    // Initialize next vertex matrix
    List<List<int>> next = List.generate(
      n,
      (i) => List.generate(n, (j) => j)
    );

    // Floyd-Warshall algorithm
    for (int k = 0; k < n; k++) {
      for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
          if (dist[i][k] + dist[k][j] < dist[i][j]) {
            dist[i][j] = dist[i][k] + dist[k][j];
            next[i][j] = next[i][k];
          }
        }
      }
    }

    // Construct optimal path
    List<LatLng> path = [points.first];
    Set<int> visited = {0};
    int current = 0;

    while (visited.length < n) {
      double minDist = double.infinity;
      int nextVertex = -1;

      for (int i = 0; i < n; i++) {
        if (!visited.contains(i) && dist[current][i] < minDist) {
          minDist = dist[current][i];
          nextVertex = i;
        }
      }

      if (nextVertex == -1) break;

      path.add(points[nextVertex]);
      visited.add(nextVertex);
      current = nextVertex;
    }

    return path;
  }

  List<LatLng> findPathDStar(List<LatLng> points) {
    if (points.isEmpty || points.length <= 2) return List.from(points);

    List<LatLng> path = [points.first];
    Set<LatLng> unvisited = Set.from(points)..remove(points.first);
    final distance = Distance();

    while (unvisited.isNotEmpty) {
      LatLng current = path.last;
      LatLng? nextPoint;
      double minCost = double.infinity;

      for (var point in unvisited) {
        double distToCurrent = distance.as(LengthUnit.Meter, current, point);
        double heuristic = 0;
        
        // Calculate heuristic based on remaining points
        if (unvisited.length > 1) {
          for (var remaining in unvisited) {
            if (remaining != point) {
              heuristic += distance.as(LengthUnit.Meter, point, remaining);
            }
          }
          heuristic /= (unvisited.length - 1);
        }

        double totalCost = distToCurrent + heuristic * 0.5; // Weighted heuristic
        if (totalCost < minCost) {
          minCost = totalCost;
          nextPoint = point;
        }
      }

      if (nextPoint != null) {
        path.add(nextPoint);
        unvisited.remove(nextPoint);
      } else {
        break;
      }
    }

    return path;
  }

  void _calculateRouteDistance() {
    if (currentRoute.length < 2) {
      currentRouteDistance = 0;
      return;
    }

    final distance = Distance();
    currentRouteDistance = 0;

    for (int i = 0; i < currentRoute.length - 1; i++) {
      currentRouteDistance += distance.as(
        LengthUnit.Meter,
        currentRoute[i],
        currentRoute[i + 1],
      );
    }
  }

  Future<void> _completeOrder(String orderId) async {
    try {
      // Update status in orders table
      await Supabase.instance.client
          .from('orders')  // table name is 'orders'
          .update({
            'status': 'completed',  // column name is 'status'
          })
          .eq('id', orderId);

      // Update local state
      setState(() {
        _nearbyOrders = _nearbyOrders.map((order) {
          if (order['id'] == orderId) {
            return {...order, 'status': 'completed'};
          }
          return order;
        }).toList();
        
        _deliveriesCompleted++;
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh the orders list
      await _fetchAssignedOrders();
      
    } catch (e) {
      print('Error completing order: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete delivery: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToOrder(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Navigation map
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    center: LatLng(
                      order['delivery_latitude'] as double,
                      order['delivery_longitude'] as double,
                    ),
                    zoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: currentRoute,
                          color: Theme.of(context).primaryColor,
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        // Current location marker
                        Marker(
                          point: LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ),
                          child: const Icon(
                            Icons.location_history,
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),
                        // Destination marker
                        Marker(
                          point: LatLng(
                            order['delivery_latitude'] as double,
                            order['delivery_longitude'] as double,
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Order details and actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delivery Address',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      order['delivery_address'],
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // Launch navigation app
                              launchUrl(Uri.parse(
                                'https://www.google.com/maps/dir/?api=1&destination=${order['delivery_latitude']},${order['delivery_longitude']}',
                              ));
                            },
                            icon: const Icon(Icons.navigation),
                            label: const Text('Start Navigation'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _completeOrder(order['id']);
                            },
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Complete Delivery'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Driver Dashboard')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ElevatedButton(
                onPressed: _initializeData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading || _currentPosition == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final isSmallScreen = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _initializeData();
            },
            tooltip: 'Refresh',
          ),
          if (isSmallScreen)
            IconButton(
              icon: Icon(_showMap ? Icons.list : Icons.map),
              onPressed: () {
                setState(() {
                  _showMap = !_showMap;
                });
              },
              tooltip: _showMap ? 'Show Orders' : 'Show Map',
            ),
        ],
      ),
      body: Column(
        children: [
          // Route Optimization Controls
          if (_nearbyOrders.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Route Optimization',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_nearbyOrders.length} Deliveries',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ...PathfindingAlgorithm.values.map((algo) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(algo.name),
                              selected: currentAlgorithm == algo,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    currentAlgorithm = algo;
                                    _calculateOptimalRoute();
                                  });
                                }
                              },
                            ),
                          );
                        }),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _calculateOptimalRoute,
                          icon: const Icon(Icons.route),
                          label: const Text('Optimize Route'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (currentRoute.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.straight, 
                          color: Theme.of(context).primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Total Distance: ${(currentRouteDistance / 1000).toStringAsFixed(2)} km',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          // Main Content Area
          Expanded(
            child: isSmallScreen
                ? _showMap
                    ? _buildMapSection(currentLocation)
                    : _buildOrdersList()
                : Row(
                    children: [
                      SizedBox(
                        width: 350,
                        child: _buildOrdersList(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _buildMapSection(currentLocation),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // Extracted Orders List Widget
  Widget _buildOrdersList() {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Summary Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.route,
                        color: Theme.of(context).primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Today\'s Deliveries',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_nearbyOrders.length} stops • ${(currentRouteDistance / 1000).toStringAsFixed(1)} km total',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Orders List
          Expanded(
            child: _nearbyOrders.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _nearbyOrders.length,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemBuilder: (context, index) {
                      final order = _nearbyOrders[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).primaryColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Stop ${index + 1} of ${_nearbyOrders.length}',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          order['delivery_address'],
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  _buildInfoChip(
                                    Icons.local_shipping,
                                    'Order #${order['id'].toString().substring(0, 8)}',
                                  ),
                                  const SizedBox(width: 12),
                                  if (order['estimated_time'] != null)
                                    _buildInfoChip(
                                      Icons.access_time,
                                      '${order['estimated_time']} min',
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _navigateToOrder(order),
                                    icon: const Icon(Icons.directions),
                                    label: const Text('Navigate'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => _completeOrder(order['id']),
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Complete'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_shipping_outlined,
              size: 48,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Deliveries Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'New deliveries will appear here',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _initializeData,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Extracted Map Widget
  Widget _buildMapSection(LatLng currentLocation) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            center: currentLocation,
            zoom: 13,
            minZoom: 3,
            maxZoom: 18,
            interactiveFlags: InteractiveFlag.all,
          ),
          children: [
            // Base map layer
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.app',
              backgroundColor: Colors.grey[200],
            ),
            // Route layer with improved visibility
            if (currentRoute.isNotEmpty) ...[
              // Route shadow for better visibility
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: currentRoute,
                    color: Colors.black.withOpacity(0.3),
                    strokeWidth: 6,
                  ),
                ],
              ),
              // Main route line
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: currentRoute,
                    color: Theme.of(context).primaryColor,
                    strokeWidth: 4,
                    gradientColors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withBlue(255),
                    ],
                  ),
                ],
              ),
            ],
            // Enhanced markers layer
            MarkerLayer(
              markers: [
                // Current location marker
                Marker(
                  point: currentLocation,
                  width: 60,
                  height: 60,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[700],
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.location_history,
                        color: Colors.blue,
                        size: 30,
                        shadows: [
                          Shadow(
                            color: Colors.white,
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Delivery stop markers
                ..._nearbyOrders.asMap().entries.map(
                  (entry) {
                    final index = entry.key;
                    final order = entry.value;
                    return Marker(
                      point: LatLng(
                        order['delivery_latitude'] as double,
                        order['delivery_longitude'] as double,
                      ),
                      width: 60,
                      height: 60,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).primaryColor,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              'Stop ${index + 1}',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.location_on,
                            color: Theme.of(context).primaryColor,
                            size: 30,
                            shadows: const [
                              Shadow(
                                color: Colors.white,
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        // Enhanced map controls
        Positioned(
          right: 16,
          top: 16,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          icon: Icon(
                            _showSatellite ? Icons.map : Icons.satellite,
                            color: Theme.of(context).primaryColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _showSatellite = !_showSatellite;
                            });
                          },
                          tooltip: _showSatellite ? 'Show Map' : 'Show Satellite',
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          icon: Icon(
                            Icons.my_location,
                            color: Theme.of(context).primaryColor,
                          ),
                          onPressed: () {
                            _mapController.move(currentLocation, 13);
                          },
                          tooltip: 'My Location',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceMetrics() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricCard(
            'Time Saved',
            '$_estimatedTimeReduction min',
            Icons.timer,
          ),
          _buildMetricCard(
            'Fuel Saved',
            '${_fuelSaved.toStringAsFixed(1)}L',
            Icons.local_gas_station,
          ),
          _buildMetricCard(
            'Deliveries',
            '$_deliveriesCompleted',
            Icons.local_shipping,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
} 